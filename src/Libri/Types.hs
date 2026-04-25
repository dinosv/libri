{-# LANGUAGE TemplateHaskell #-}

module Libri.Types
  ( -- * Core Types
    Book (..)
  , BookId
  , Location
  , Config (..)
  , AppState (..)
  , LibriError (..)
    -- * Lenses
  , bookId
  , isbn
  , title
  , authors
  , series
  , seriesIndex
  , publisher
  , published
  , tags
  , rating
  , comments
  , location
  , custom
  , added
  , modified
    -- * Config Lenses
  , dataDir
  , defaultLocation
  , isbnApi
  , fuzzyThreshold
    -- * AppState Lenses
  , books
  , locations
  , config
  , selectedIndex
  , searchQuery
  , currentView
  , sortField
  , sortOrder
  , activeFilter
  , groupMode
    -- * View Types
  , View (..)
    -- * Sort Types
  , SortField (..)
  , SortOrder (..)
    -- * Filter Types
  , Filter (..)
  , GroupField (..)
    -- * Helper Functions
  , newBook
  , defaultConfig
  , bookFilename
  ) where

import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , Value
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.=)
  )
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, UTCTime, getCurrentTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import GHC.Generics (Generic)
import Lens.Micro.TH (makeLenses)

-- | Unique identifier for a book (UUID or ISBN)
type BookId = Text

-- | Physical location identifier
type Location = Text

-- | Core book data type
data Book = Book
  { _bookId :: BookId
  , _isbn :: Maybe Text
  , _title :: Text
  , _authors :: [Text]
  , _series :: Maybe Text
  , _seriesIndex :: Maybe Double
  , _publisher :: Maybe Text
  , _published :: Maybe Day
  , _tags :: [Text]
  , _rating :: Maybe Int
  , _comments :: Maybe Text
  , _location :: Maybe Location
  , _custom :: Map Text Value
  , _added :: UTCTime
  , _modified :: UTCTime
  }
  deriving (Show, Eq, Generic)

makeLenses ''Book

instance ToJSON Book where
  toJSON Book {..} =
    object
      [ "id" .= _bookId
      , "isbn" .= _isbn
      , "title" .= _title
      , "authors" .= _authors
      , "series" .= _series
      , "seriesIndex" .= _seriesIndex
      , "publisher" .= _publisher
      , "published" .= _published
      , "tags" .= _tags
      , "rating" .= _rating
      , "comments" .= _comments
      , "location" .= _location
      , "custom" .= _custom
      , "added" .= _added
      , "modified" .= _modified
      ]

instance FromJSON Book where
  parseJSON = withObject "Book" $ \v ->
    Book
      <$> v .: "id"
      <*> v .:? "isbn"
      <*> v .: "title"
      <*> v .: "authors"
      <*> v .:? "series"
      <*> v .:? "seriesIndex"
      <*> v .:? "publisher"
      <*> v .:? "published"
      <*> (v .:? "tags" >>= pure . maybe [] id)
      <*> v .:? "rating"
      <*> v .:? "comments"
      <*> v .:? "location"
      <*> (v .:? "custom" >>= pure . maybe Map.empty id)
      <*> v .: "added"
      <*> v .: "modified"

-- | Application configuration
data Config = Config
  { _dataDir :: FilePath
  , _defaultLocation :: Maybe Location
  , _isbnApi :: Text
  , _fuzzyThreshold :: Double
  }
  deriving (Show, Eq, Generic)

makeLenses ''Config

instance ToJSON Config where
  toJSON Config {..} =
    object
      [ "dataDir" .= _dataDir
      , "defaultLocation" .= _defaultLocation
      , "isbnApi" .= _isbnApi
      , "fuzzyThreshold" .= _fuzzyThreshold
      ]

instance FromJSON Config where
  parseJSON = withObject "Config" $ \v ->
    Config
      <$> v .: "dataDir"
      <*> v .:? "defaultLocation"
      <*> (v .:? "isbnApi" >>= pure . maybe "openlibrary" id)
      <*> (v .:? "fuzzyThreshold" >>= pure . maybe 0.6 id)

-- | Sort field options
data SortField = SortByTitle | SortByAuthor | SortByDate
  deriving (Show, Eq)

-- | Sort order options
data SortOrder = Ascending | Descending
  deriving (Show, Eq)

-- | Filter for narrowing the book list
data Filter
  = FilterTag Text
  | FilterAuthor Text
  deriving (Show, Eq)

-- | Field to group books by
data GroupField = GroupByTag | GroupByAuthor
  deriving (Show, Eq)

-- | Different views in the TUI
data View
  = ViewList
  | ViewSearch
  | ViewCommand
  | ViewAdd
  | ViewEdit BookId
  | ViewMove BookId
  | ViewHelp
  deriving (Show, Eq)

-- | Application state for TUI
data AppState = AppState
  { _books :: [Book]
  , _locations :: [Location]
  , _config :: Config
  , _selectedIndex :: Int
  , _searchQuery :: Text
  , _currentView :: View
  , _sortField :: SortField
  , _sortOrder :: SortOrder
  , _activeFilter :: Maybe Filter
  , _groupMode :: Maybe GroupField
  }
  deriving (Show)

makeLenses ''AppState

-- | Errors that can occur in the application
data LibriError
  = FileNotFound FilePath
  | ParseError FilePath String
  | NetworkError String
  | ISBNNotFound Text
  | BookNotFound BookId
  | InvalidISBN Text
  | CalibreImportError String
  deriving (Show, Eq)

-- | Create a new book with default values
newBook :: IO Book
newBook = do
  uuid <- UUID.nextRandom
  now <- getCurrentTime
  pure
    Book
      { _bookId = UUID.toText uuid
      , _isbn = Nothing
      , _title = ""
      , _authors = []
      , _series = Nothing
      , _seriesIndex = Nothing
      , _publisher = Nothing
      , _published = Nothing
      , _tags = []
      , _rating = Nothing
      , _comments = Nothing
      , _location = Nothing
      , _custom = Map.empty
      , _added = now
      , _modified = now
      }

-- | Default configuration
defaultConfig :: Config
defaultConfig =
  Config
    { _dataDir = "./data"
    , _defaultLocation = Nothing
    , _isbnApi = "openlibrary"
    , _fuzzyThreshold = 0.6
    }

-- | Generate filename for a book's YAML file
bookFilename :: Book -> FilePath
bookFilename book =
  let baseId = _bookId book
      sanitized = T.unpack $ T.replace "/" "-" $ T.replace " " "_" baseId
   in sanitized <> ".yaml"
