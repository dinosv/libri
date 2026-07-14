module Libri.Storage.CalibreImport
  ( importFromCalibre
  , saveImportedBooks
  , CalibreBook (..)
  , extractIsbn
  , partitionIdentifiers
  ) where

import Control.Applicative ((<|>))
import Control.Exception (bracket, try, SomeException)
import Control.Monad (forM)
import Data.Aeson (Value (..))
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, listToMaybe, mapMaybe)
import Data.Scientific (fromFloatDigits)
import qualified Data.Vector as V
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, UTCTime, getCurrentTime, parseTimeM, defaultTimeLocale)
import Database.SQLite.Simple
import Libri.Types (Book (..), Config, LibriError (..), bookFilename)
import Libri.Storage.Yaml (loadBook, saveBook, mergeBooks, getDataDir)
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

-- | Import books from a Calibre library
importFromCalibre :: FilePath -> IO (Either LibriError [Book])
importFromCalibre libraryPath = do
  let dbPath = libraryPath </> "metadata.db"
  exists <- doesFileExist dbPath
  if not exists
    then pure $ Left $ FileNotFound dbPath
    else do
      result <- try $ importBooks dbPath
      case result of
        Left (e :: SomeException) ->
          pure $ Left $ CalibreImportError (show e)
        Right books -> pure $ Right books

-- | Import all books from the database
importBooks :: FilePath -> IO [Book]
importBooks dbPath = bracket (open dbPath) close $ \conn -> do
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

    convertBook cb authorList identifiers tagList seriesName pub rat comm customCols

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
    \WHERE btl.book = ?" (Only bid) :: IO [Only T.Text]
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
  :: CalibreBook
  -> [T.Text]
  -> [(T.Text, T.Text)]
  -> [T.Text]
  -> Maybe T.Text
  -> Maybe T.Text
  -> Maybe Int
  -> Maybe T.Text
  -> Map.Map T.Text Value
  -> IO Book
convertBook cb authorList identifiers tagList seriesName pub rat comm customCols = do
  now <- getCurrentTime

  let pubDate = cbPubdate cb >>= parseDate

  let (maybeIsbn, otherIds) = partitionIdentifiers identifiers
      customWithIds = Map.union
        (Map.map String otherIds)
        (Map.delete "location" customCols)

  pure
    Book
      { _bookId = T.pack $ show (cbId cb)
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
      , _added = fromMaybe now (cbTimestamp cb)
      , _modified = cbLastModified cb
      }

-- | Parse a date string from Calibre
parseDate :: T.Text -> Maybe Day
parseDate t =
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
  let isbns = [val | (typ, val) <- ids, typ == "isbn"]
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

-- | Save imported books, merging with existing if present
saveImportedBooks :: Config -> [Book] -> IO [Either LibriError ()]
saveImportedBooks cfg books = do
  dir <- getDataDir cfg
  let booksDir = dir </> "books"
  forM books $ \book -> do
    let filename = bookFilename book
        path = booksDir </> filename
    existingResult <- loadBook path
    let bookToSave = case existingResult of
          Right existing -> mergeBooks book existing
          Left _ -> book  -- No existing book, use as-is
    saveBook cfg bookToSave
