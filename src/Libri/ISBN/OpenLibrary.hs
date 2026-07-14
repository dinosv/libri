module Libri.ISBN.OpenLibrary
  ( fetchByISBN
  , fetchByISBNWith
  , newISBNManager
  , OpenLibraryBook (..)
  ) where

import Control.Exception (try, SomeException)
import Control.Monad (forM)
import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, getCurrentTime, parseTimeM, defaultTimeLocale)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import Libri.Types
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)

-- | Response from Open Library ISBN endpoint
data OpenLibraryBook = OpenLibraryBook
  { olTitle :: Text
  , olAuthorKeys :: [Text]      -- Author keys like "/authors/OL123A"
  , olPublishers :: [Text]
  , olPublishDate :: Maybe Text
  , olNumberOfPages :: Maybe Int
  , olSubjects :: [Text]
  , olDescription :: Maybe Text
  }
  deriving (Show)

instance FromJSON OpenLibraryBook where
  parseJSON = withObject "OpenLibraryBook" $ \v -> do
    olTitle <- v .: "title"

    -- Authors are objects with "key" field
    authorsRaw <- v .:? "authors" .!= []
    olAuthorKeys <- parseAuthorKeys authorsRaw

    olPublishers <- v .:? "publishers" .!= []
    olPublishDate <- v .:? "publish_date"
    olNumberOfPages <- v .:? "number_of_pages"

    -- Subjects can be strings or objects
    subjectsRaw <- v .:? "subjects" .!= []
    olSubjects <- parseSubjects subjectsRaw

    -- Description can be a string or an object with "value"
    descRaw <- v .:? "description"
    let olDescription = parseDescription descRaw

    pure OpenLibraryBook {..}

-- | Parse author keys from various formats
parseAuthorKeys :: [Value] -> Parser [Text]
parseAuthorKeys = fmap catMaybes . mapM parseAuthorKey
  where
    parseAuthorKey (Object o) = o .:? "key"
    parseAuthorKey _ = pure Nothing

-- | Parse subjects from various formats, dropping malformed entries
-- instead of turning them into empty tags
parseSubjects :: [Value] -> Parser [Text]
parseSubjects = fmap (filter (not . T.null)) . mapM parseSubject
  where
    parseSubject (Object o) = o .:? "name" .!= ""
    parseSubject (String s) = pure s
    parseSubject _ = pure ""

-- | Parse description from string or object
parseDescription :: Maybe Value -> Maybe Text
parseDescription Nothing = Nothing
parseDescription (Just (String s)) = Just s
parseDescription (Just (Object o)) =
  case fromJSON (Object o) of
    Success desc -> Just desc
    Error _ -> Nothing
parseDescription _ = Nothing

-- | Create a reusable HTTP manager for ISBN lookups
newISBNManager :: IO Manager
newISBNManager = newManager tlsManagerSettings

-- | Fetch book metadata by ISBN (creates a fresh HTTP manager)
fetchByISBN :: Text -> IO (Either LibriError Book)
fetchByISBN isbnText = do
  mgr <- newISBNManager
  fetchByISBNWith mgr isbnText

-- | Fetch book metadata by ISBN using an existing HTTP manager
fetchByISBNWith :: Manager -> Text -> IO (Either LibriError Book)
fetchByISBNWith mgr isbnText = do
  let cleanISBN = T.filter (\c -> c /= '-' && c /= ' ') isbnText
      url = "https://openlibrary.org/isbn/" <> T.unpack cleanISBN <> ".json"

  result <- try $ do
    request <- parseRequest url
    response <- httpLbs request mgr

    let status = statusCode $ responseStatus response
    if status == 404
      then pure $ Left $ ISBNNotFound isbnText
      else if status /= 200
        then pure $ Left $ NetworkError $ "HTTP " <> show status
        else do
          case eitherDecode (responseBody response) of
            Left err -> pure $ Left $ ParseError url err
            Right olBook -> do
              authorNames <- fetchAuthorNames mgr (olAuthorKeys olBook)
              book <- convertToBook cleanISBN olBook authorNames
              pure $ Right book

  case result of
    Left (e :: SomeException) -> pure $ Left $ NetworkError (show e)
    Right r -> pure r

-- | Fetch author names from author keys
fetchAuthorNames :: Manager -> [Text] -> IO [Text]
fetchAuthorNames manager keys = do
  names <- forM keys $ \key -> do
    let url = "https://openlibrary.org" <> T.unpack key <> ".json"
    result <- try $ do
      request <- parseRequest url
      response <- httpLbs request manager
      let status = statusCode $ responseStatus response
      if status == 200
        then case eitherDecode (responseBody response) of
          Right (Object o) -> case fromJSON (Object o) of
            Success (AuthorResponse name) -> pure $ Just name
            _ -> pure Nothing
          _ -> pure Nothing
        else pure Nothing
    case result of
      Left (_ :: SomeException) -> pure Nothing
      Right r -> pure r
  pure $ catMaybes names

-- | Helper type for parsing author response
newtype AuthorResponse = AuthorResponse Text

instance FromJSON AuthorResponse where
  parseJSON = withObject "AuthorResponse" $ \v -> do
    name <- v .: "name"
    pure $ AuthorResponse name

-- | Convert Open Library response to our Book type
convertToBook :: Text -> OpenLibraryBook -> [Text] -> IO Book
convertToBook isbnText olBook authorNames = do
  now <- getCurrentTime
  uuid <- UUID.nextRandom

  let pubDate = olPublishDate olBook >>= parsePublishDate

  pure Book
    { _bookId = UUID.toText uuid
    , _isbn = Just isbnText
    , _title = olTitle olBook
    , _authors = authorNames
    , _series = Nothing
    , _seriesIndex = Nothing
    , _publisher = case olPublishers olBook of
        [] -> Nothing
        (p:_) -> Just p
    , _published = pubDate
    , _tags = take 10 $ olSubjects olBook  -- Limit tags
    , _rating = Nothing
    , _comments = olDescription olBook
    , _location = Nothing
    , _custom = mempty
    , _added = now
    , _modified = now
    }

-- | Try to parse various date formats from Open Library
parsePublishDate :: Text -> Maybe Day
parsePublishDate t =
  let str = T.unpack t
  in tryFormats str
    [ "%B %d, %Y"      -- "January 1, 2020"
    , "%B %Y"          -- "January 2020"
    , "%Y-%m-%d"       -- "2020-01-01"
    , "%Y"             -- "2020"
    , "%d %B %Y"       -- "1 January 2020"
    ]
  where
    tryFormats _ [] = Nothing
    tryFormats s (fmt:fmts) =
      case parseTimeM True defaultTimeLocale fmt s of
        Just d -> Just d
        Nothing -> tryFormats s fmts
