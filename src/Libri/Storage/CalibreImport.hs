module Libri.Storage.CalibreImport
  ( importFromCalibre
  , CalibreLibrary (..)
  , CalibreBook (..)
  , extractIsbn
  , partitionIdentifiers
  , calibreIdentifier
  , parseDate
  ) where

import Control.Applicative ((<|>))
import Control.Exception (bracket, try, SomeException)
import Control.Monad (forM)
import Data.Aeson (Value (..))
import qualified Data.Map.Strict as Map
import Data.Char (isSpace)
import Data.Maybe (catMaybes, fromMaybe, listToMaybe, mapMaybe)
import Data.Scientific (fromFloatDigits)
import qualified Data.Vector as V
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, UTCTime (..), getCurrentTime, parseTimeM, defaultTimeLocale, toGregorian)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import Database.SQLite.Simple
import Libri.Types (Book (..), LibriError (..))
import System.Directory (doesFileExist)
import System.FilePath ((</>))

-- | Intermediate type for Calibre book data
data CalibreBook = CalibreBook
  { cbId :: Int
  , cbTitle :: Text
  , cbSort :: Maybe Text
  , cbTimestamp :: Maybe UTCTime
  , cbPubdate :: Maybe Text
  , cbSeriesIndex :: Maybe Double
  , cbPath :: Text
  , cbHascover :: Bool
  , cbLastModified :: UTCTime
  }
  deriving (Show)

instance FromRow CalibreBook where
  fromRow =
    CalibreBook
      <$> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field

-- | A Calibre library read from disk: its own UUID, the path it was
-- read from, and its books
data CalibreLibrary = CalibreLibrary
  { clUuid :: Text
  , clPath :: FilePath
  , clBooks :: [Book]
  }
  deriving (Show)

-- | Import books from a Calibre library
importFromCalibre :: FilePath -> IO (Either LibriError CalibreLibrary)
importFromCalibre libraryPath = do
  let dbPath = libraryPath </> "metadata.db"
  exists <- doesFileExist dbPath
  if not exists
    then pure $ Left $ FileNotFound dbPath
    else do
      result <- try $ importBooks libraryPath dbPath
      case result of
        Left (e :: SomeException) ->
          pure $ Left $ CalibreImportError (show e)
        Right (Left err) -> pure $ Left err
        Right (Right books) -> pure $ Right books
-- | Import all books from the database; fails when the library has no UUID
importBooks :: FilePath -> FilePath -> IO (Either LibriError CalibreLibrary)
importBooks libraryPath dbPath = bracket (open dbPath) close $ \conn -> do
  mUuid <- getLibraryUuid conn
  case mUuid of
    Nothing -> pure $ Left $ CalibreImportError "Calibre library has no library UUID"
    Just libraryUuid -> do
      books <- importBooksFor conn libraryUuid
      pure $ Right CalibreLibrary
        { clUuid = libraryUuid, clPath = libraryPath, clBooks = books }

-- | Read every book in the library
importBooksFor :: Connection -> T.Text -> IO [Book]
importBooksFor conn libraryUuid = do
  calibreBooks <- query_ conn
    "SELECT id, title, sort, timestamp, pubdate, series_index, path, has_cover, last_modified \
    \FROM books" :: IO [CalibreBook]

  forM calibreBooks $ \cb -> do
    authorList <- getAuthors conn (cbId cb)
    identifiers <- getIdentifiers conn (cbId cb)
    tagList <- getTags conn (cbId cb)
    seriesName <- getSeries conn (cbId cb)
    pub <- getPublisher conn (cbId cb)
    rat <- getRating conn (cbId cb)
    comm <- getComments conn (cbId cb)
    customCols <- getCustomColumns conn (cbId cb)

    convertBook libraryUuid cb authorList identifiers tagList seriesName pub rat comm customCols

-- | The Calibre library's own UUID, used to namespace book identifiers
-- so imports from different libraries can never be confused
getLibraryUuid :: Connection -> IO (Maybe T.Text)
getLibraryUuid conn = do
  result <- try (query_ conn "SELECT uuid FROM library_id LIMIT 1")
    :: IO (Either SomeException [Only T.Text])
  pure $ case result of
    Right (Only u : _) | not (T.null (T.strip u)) -> Just u
    _ -> Nothing

-- | Get authors for a book
getAuthors :: Connection -> Int -> IO [T.Text]
getAuthors conn bid = do
  rows <- query conn
    "SELECT a.name FROM authors a \
    \JOIN books_authors_link bal ON a.id = bal.author \
    \WHERE bal.book = ? \
    \ORDER BY bal.id" (Only bid) :: IO [Only T.Text]
  pure $ map fromOnly rows

-- | Get identifiers for a book (ISBN, Amazon, Google, etc.)
getIdentifiers :: Connection -> Int -> IO [(T.Text, T.Text)]
getIdentifiers conn bid = do
  result <- try $ query conn
    "SELECT type, val FROM identifiers WHERE book = ?"
    (Only bid) :: IO (Either SomeException [(T.Text, T.Text)])
  case result of
    Left _ -> pure []
    Right rows -> pure rows

-- | Get tags for a book
getTags :: Connection -> Int -> IO [T.Text]
getTags conn bid = do
  rows <- query conn
    "SELECT t.name FROM tags t \
    \JOIN books_tags_link btl ON t.id = btl.tag \
    \WHERE btl.book = ? \
    \ORDER BY t.name" (Only bid) :: IO [Only T.Text]
  pure $ map fromOnly rows

-- | Get series name for a book
getSeries :: Connection -> Int -> IO (Maybe T.Text)
getSeries conn bid = do
  rows <- query conn
    "SELECT s.name FROM series s \
    \JOIN books_series_link bsl ON s.id = bsl.series \
    \WHERE bsl.book = ?" (Only bid) :: IO [Only T.Text]
  pure $ fmap fromOnly (listToMaybe rows)

-- | Get publisher for a book
getPublisher :: Connection -> Int -> IO (Maybe T.Text)
getPublisher conn bid = do
  rows <- query conn
    "SELECT p.name FROM publishers p \
    \JOIN books_publishers_link bpl ON p.id = bpl.publisher \
    \WHERE bpl.book = ?" (Only bid) :: IO [Only T.Text]
  pure $ fmap fromOnly (listToMaybe rows)

-- | Get rating for a book (Calibre stores 0-10, we use 1-5)
getRating :: Connection -> Int -> IO (Maybe Int)
getRating conn bid = do
  rows <- query conn
    "SELECT r.rating FROM ratings r \
    \JOIN books_ratings_link brl ON r.id = brl.rating \
    \WHERE brl.book = ?" (Only bid) :: IO [Only Int]
  pure $ case listToMaybe rows of
    Nothing -> Nothing
    Just (Only r)
      | r <= 0    -> Nothing
      | otherwise -> Just $ max 1 (min 5 (r `div` 2))

-- | Get comments for a book
getComments :: Connection -> Int -> IO (Maybe T.Text)
getComments conn bid = do
  rows <- query conn
    "SELECT text FROM comments WHERE book = ?" (Only bid) :: IO [Only T.Text]
  pure $ fmap fromOnly (listToMaybe rows)

-- | Get custom column values for a book
getCustomColumns :: Connection -> Int -> IO (Map.Map T.Text Value)
getCustomColumns conn bid = do
  cols <- query_ conn
    "SELECT id, label, name, datatype FROM custom_columns" :: IO [(Int, T.Text, T.Text, T.Text)]

  pairs <- forM cols $ \(colId, label, _name, datatype) -> do
    val <- getCustomValue conn colId bid datatype
    pure $ case val of
      Nothing -> Nothing
      Just v -> Just (label, v)

  pure $ Map.fromList $ catMaybes pairs

-- | Get a single custom column value.
-- Calibre stores plain columns (int, float, bool, datetime, long text)
-- directly in @custom_column_N(book, value)@, but normalized columns
-- (text, enumeration, series -- including multi-value columns) keep values
-- in @custom_column_N(id, value)@ joined via @books_custom_column_N_link@.
getCustomValue :: Connection -> Int -> Int -> T.Text -> IO (Maybe Value)
getCustomValue conn colId bid datatype = do
  let tbl = "custom_column_" <> show colId
      linkTbl = "books_custom_column_" <> show colId <> "_link"
      directQ = Query $ T.pack $
        "SELECT value FROM " <> tbl <> " WHERE book = ?"
      linkedQ = Query $ T.pack $
        "SELECT cc.value FROM " <> tbl <> " cc JOIN " <> linkTbl
        <> " l ON l.value = cc.id WHERE l.book = ?"
  direct <- tryQuery directQ
  rows <- case direct of
    Right rs -> pure rs
    Left _ -> either (const []) id <$> tryQuery linkedQ
  pure $ case mapMaybe (sqlToValue datatype) rows of
    []  -> Nothing
    [v] -> Just v
    vs  -> Just $ Array (V.fromList vs)
  where
    tryQuery q = fmap (map fromOnly) <$>
      (try (query conn q (Only bid)) :: IO (Either SomeException [Only SQLData]))

-- | Convert a raw SQLite value to JSON, using the column datatype
-- to distinguish booleans from plain integers
sqlToValue :: T.Text -> SQLData -> Maybe Value
sqlToValue datatype sql = case sql of
  SQLText t -> Just $ String t
  SQLInteger i
    | datatype == "bool" -> Just $ Bool (i /= 0)
    | otherwise -> Just $ Number (fromIntegral i)
  SQLFloat d -> Just $ Number (fromFloatDigits d)
  SQLBlob _ -> Nothing
  SQLNull -> Nothing

-- | Convert a Calibre book to our Book type
convertBook
  :: T.Text
  -> CalibreBook
  -> [T.Text]
  -> [(T.Text, T.Text)]
  -> [T.Text]
  -> Maybe T.Text
  -> Maybe T.Text
  -> Maybe Int
  -> Maybe T.Text
  -> Map.Map T.Text Value
  -> IO Book
convertBook libraryUuid cb authorList identifiers tagList seriesName pub rat comm customCols = do
  now <- getCurrentTime
  uuid <- UUID.nextRandom

  let pubDate = cbPubdate cb >>= parseDate
      addedAt = cbTimestamp cb >>= validTimestamp

  let (maybeIsbn, otherIds) = partitionIdentifiers identifiers
      calibreRef = calibreIdentifier libraryUuid (cbId cb)
      customWithIds = Map.insert "identifier:calibre" (String calibreRef) $
        Map.union
          (Map.map String otherIds)
          (Map.delete "location" customCols)

  pure
    Book
      { _bookId = UUID.toText uuid
      , _isbn = maybeIsbn
      , _title = cbTitle cb
      , _authors = authorList
      , _series = seriesName
      , _seriesIndex = cbSeriesIndex cb
      , _publisher = pub
      , _published = pubDate
      , _tags = tagList
      , _rating = rat
      , _comments = comm
      , _location = Map.lookup "location" customCols >>= valueToText
      , _custom = customWithIds
      , _added = fromMaybe now addedAt
      , _modified = cbLastModified cb
      }

-- | Calibre stores 0101-01-01 when a date is unset; treat years before
-- 1000 as no date
validTimestamp :: UTCTime -> Maybe UTCTime
validTimestamp t
  | utctYear t < 1000 = Nothing
  | otherwise = Just t
  where utctYear = (\(y, _, _) -> y) . toGregorian . utctDay

-- | Parse a date string from Calibre; Nothing for unparseable dates and
-- Calibre's 0101-01-01 "unset" sentinel
parseDate :: T.Text -> Maybe Day
parseDate t = do
  d <- parseRawDate t
  let (y, _, _) = toGregorian d
  if y < 1000 then Nothing else Just d

parseRawDate :: T.Text -> Maybe Day
parseRawDate t =
  let str = T.unpack t
   in parseTimeM True defaultTimeLocale "%Y-%m-%d" str
        <|> parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S" str
        <|> parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%Q%z" str
        <|> parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%z" str
        <|> parseTimeM True defaultTimeLocale "%Y-%m-%d %H:%M:%S%Q%z" str
        <|> parseTimeM True defaultTimeLocale "%Y-%m-%d %H:%M:%S%z" str
        <|> parseTimeM True defaultTimeLocale "%Y-%m-%d %H:%M:%S" str
        <|> parseTimeM True defaultTimeLocale "%Y" str

-- | Extract text from a JSON Value
valueToText :: Value -> Maybe T.Text
valueToText (String t) = Just t
valueToText _ = Nothing

-- | Extract ISBN from a list of identifiers, preferring ISBN-13
extractIsbn :: [(T.Text, T.Text)] -> Maybe T.Text
extractIsbn ids =
  let normalise = T.toUpper . T.filter (\c -> not (isSpace c) && c /= '-')
      isbns = [normalise val | (typ, val) <- ids, typ == "isbn"]
      isbn13s = filter (\v -> T.length v == 13) isbns
      isbn10s = filter (\v -> T.length v == 10) isbns
   in case isbn13s of
        (x : _) -> Just x
        [] -> case isbn10s of
          (x : _) -> Just x
          [] -> Nothing

-- | Partition identifiers into ISBN and other identifiers
partitionIdentifiers :: [(T.Text, T.Text)] -> (Maybe T.Text, Map.Map T.Text T.Text)
partitionIdentifiers ids =
  let maybeIsbn = extractIsbn ids
      others = [(T.pack "identifier:" <> typ, val) | (typ, val) <- ids, typ /= "isbn"]
   in (maybeIsbn, Map.fromList others)

-- | Namespaced Calibre book reference: "<libraryUuid>:<bookId>"
calibreIdentifier :: T.Text -> Int -> T.Text
calibreIdentifier libraryUuid bid =
  libraryUuid <> ":" <> T.pack (show bid)
