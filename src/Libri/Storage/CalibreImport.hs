module Libri.Storage.CalibreImport
  ( importFromCalibre
  , CalibreBook (..)
  , extractIsbn
  , partitionIdentifiers
  ) where

import Control.Exception (try, SomeException)
import Control.Monad (forM)
import Data.Aeson (Value (..), toJSON)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, UTCTime, getCurrentTime, parseTimeM, defaultTimeLocale)
import Database.SQLite.Simple
import Database.SQLite.Simple.FromRow
import Lens.Micro ((&), (.~))
import Libri.Types
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
importBooks dbPath = do
  conn <- open dbPath

  -- Get all books
  calibreBooks <- query_ conn
    "SELECT id, title, sort, timestamp, pubdate, series_index, path, has_cover, last_modified \
    \FROM books" :: IO [CalibreBook]

  -- Convert each book
  books <- forM calibreBooks $ \cb -> do
    authors <- getAuthors conn (cbId cb)
    tags <- getTags conn (cbId cb)
    series <- getSeries conn (cbId cb)
    publisher <- getPublisher conn (cbId cb)
    rating <- getRating conn (cbId cb)
    comments <- getComments conn (cbId cb)
    customCols <- getCustomColumns conn (cbId cb)

    convertBook cb authors tags series publisher rating comments customCols

  close conn
  pure books

-- | Get authors for a book
getAuthors :: Connection -> Int -> IO [Text]
getAuthors conn bookId = do
  rows <- query conn
    "SELECT a.name FROM authors a \
    \JOIN books_authors_link bal ON a.id = bal.author \
    \WHERE bal.book = ? \
    \ORDER BY bal.id" (Only bookId) :: IO [Only Text]
  pure $ map fromOnly rows

-- | Get tags for a book
getTags :: Connection -> Int -> IO [Text]
getTags conn bookId = do
  rows <- query conn
    "SELECT t.name FROM tags t \
    \JOIN books_tags_link btl ON t.id = btl.tag \
    \WHERE btl.book = ?" (Only bookId) :: IO [Only Text]
  pure $ map fromOnly rows

-- | Get series name for a book
getSeries :: Connection -> Int -> IO (Maybe Text)
getSeries conn bookId = do
  rows <- query conn
    "SELECT s.name FROM series s \
    \JOIN books_series_link bsl ON s.id = bsl.series \
    \WHERE bsl.book = ?" (Only bookId) :: IO [Only Text]
  pure $ fmap fromOnly (listToMaybe rows)

-- | Get publisher for a book
getPublisher :: Connection -> Int -> IO (Maybe Text)
getPublisher conn bookId = do
  rows <- query conn
    "SELECT p.name FROM publishers p \
    \JOIN books_publishers_link bpl ON p.id = bpl.publisher \
    \WHERE bpl.book = ?" (Only bookId) :: IO [Only Text]
  pure $ fmap fromOnly (listToMaybe rows)

-- | Get rating for a book (Calibre stores 0-10, we use 1-5)
getRating :: Connection -> Int -> IO (Maybe Int)
getRating conn bookId = do
  rows <- query conn
    "SELECT r.rating FROM ratings r \
    \JOIN books_ratings_link brl ON r.id = brl.rating \
    \WHERE brl.book = ?" (Only bookId) :: IO [Only Int]
  pure $ fmap (\(Only r) -> max 1 (min 5 (r `div` 2))) (listToMaybe rows)

-- | Get comments for a book
getComments :: Connection -> Int -> IO (Maybe Text)
getComments conn bookId = do
  rows <- query conn
    "SELECT text FROM comments WHERE book = ?" (Only bookId) :: IO [Only Text]
  pure $ fmap fromOnly (listToMaybe rows)

-- | Get custom column values for a book
getCustomColumns :: Connection -> Int -> IO (Map.Map Text Value)
getCustomColumns conn bookId = do
  -- First get all custom columns
  cols <- query_ conn
    "SELECT id, label, name, datatype FROM custom_columns" :: IO [(Int, Text, Text, Text)]

  -- For each column, get the value for this book
  pairs <- forM cols $ \(colId, label, name, datatype) -> do
    let tableName = "custom_column_" <> show colId
    val <- getCustomValue conn tableName bookId datatype
    pure $ case val of
      Nothing -> Nothing
      Just v -> Just (label, v)

  pure $ Map.fromList $ catMaybes pairs

-- | Get a single custom column value
getCustomValue :: Connection -> String -> Int -> Text -> IO (Maybe Value)
getCustomValue conn tableName bookId datatype = do
  -- This is simplified - real implementation would need to handle different datatypes
  result <- try $ query conn
    (Query $ T.pack $ "SELECT value FROM " <> tableName <> " WHERE book = ?")
    (Only bookId) :: IO (Either SomeException [Only Text])
  case result of
    Left _ -> pure Nothing
    Right [] -> pure Nothing
    Right (Only v : _) -> pure $ Just $ String v

-- | Convert a Calibre book to our Book type
convertBook
  :: CalibreBook
  -> [Text]
  -> [Text]
  -> Maybe Text
  -> Maybe Text
  -> Maybe Int
  -> Maybe Text
  -> Map.Map Text Value
  -> IO Book
convertBook cb authors tags series publisher rating comments customCols = do
  now <- getCurrentTime

  -- Try to parse the publication date
  let pubDate = cbPubdate cb >>= parseDate

  pure
    Book
      { _bookId = T.pack $ show (cbId cb)
      , _isbn = Nothing  -- Calibre stores ISBN in identifiers table, would need separate query
      , _title = cbTitle cb
      , _authors = authors
      , _series = series
      , _seriesIndex = cbSeriesIndex cb
      , _publisher = publisher
      , _published = pubDate
      , _tags = tags
      , _rating = rating
      , _comments = comments
      , _location = Map.lookup "location" customCols >>= valueToText
      , _custom = Map.delete "location" customCols
      , _added = fromMaybe now (cbTimestamp cb)
      , _modified = cbLastModified cb
      }

-- | Parse a date string from Calibre
parseDate :: Text -> Maybe Day
parseDate t =
  let str = T.unpack t
   in parseTimeM True defaultTimeLocale "%Y-%m-%d" str
        <|> parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S" str
        <|> parseTimeM True defaultTimeLocale "%Y" str
  where
    (<|>) :: Maybe a -> Maybe a -> Maybe a
    Nothing <|> y = y
    x <|> _ = x

-- | Extract text from a JSON Value
valueToText :: Value -> Maybe Text
valueToText (String t) = Just t
valueToText _ = Nothing

-- | Extract ISBN from a list of identifiers, preferring ISBN-13
extractIsbn :: [(Text, Text)] -> Maybe Text
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
-- Returns (Maybe ISBN, Map of prefixed identifiers)
partitionIdentifiers :: [(Text, Text)] -> (Maybe Text, Map.Map Text Text)
partitionIdentifiers ids =
  let maybeIsbn = extractIsbn ids
      others = [(T.pack "identifier:" <> typ, val) | (typ, val) <- ids, typ /= "isbn"]
   in (maybeIsbn, Map.fromList others)
