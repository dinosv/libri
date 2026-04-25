module TypesSpec (spec) where

import Data.Aeson (decode, encode)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Libri.Types
import Test.Hspec

spec :: Spec
spec = describe "Types" $ do
  describe "Book JSON" $ do
    it "encodes and decodes a book correctly" $ do
      let timestamp = fromJust (parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: Maybe UTCTime)
          book = Book
            { _bookId = "test-id"
            , _isbn = Just "978-0-13-468599-1"
            , _title = "Test Book"
            , _authors = ["Author One", "Author Two"]
            , _series = Just "Test Series"
            , _seriesIndex = Just 1.0
            , _publisher = Just "Test Publisher"
            , _published = Nothing
            , _tags = ["tag1", "tag2"]
            , _rating = Just 4
            , _comments = Just "A test comment"
            , _location = Just "Shelf A"
            , _custom = Map.empty
            , _added = timestamp
            , _modified = timestamp
            }
          encoded = encode book
          decoded = decode encoded :: Maybe Book

      decoded `shouldBe` Just book

  describe "Config JSON" $ do
    it "encodes and decodes config correctly" $ do
      let cfg = Config
            { _dataDir = "/test/path"
            , _defaultLocation = Just "Default Shelf"
            , _isbnApi = "openlibrary"
            , _fuzzyThreshold = 0.7
            }
          encoded = encode cfg
          decoded = decode encoded :: Maybe Config

      decoded `shouldBe` Just cfg

    it "uses defaults for missing optional fields" $ do
      let cfg = defaultConfig
      _isbnApi cfg `shouldBe` "openlibrary"
      _fuzzyThreshold cfg `shouldBe` 0.6
