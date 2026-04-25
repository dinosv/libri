module YamlSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Aeson (Value(..))
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Libri.Storage.Yaml (mergeBooks)
import Libri.Types (Book(..))
import Test.Hspec

spec :: Spec
spec = describe "YAML Storage" $ do

  describe "mergeBooks" $ do
    let testTime1 = UTCTime (fromGregorian 2025 1 1) 0
        testTime2 = UTCTime (fromGregorian 2025 1 2) 0
        calibreBook = Book
          { _bookId = "calibre-42"
          , _isbn = Just "9780134685991"
          , _title = "Updated Title"
          , _authors = ["New Author"]
          , _series = Just "Series"
          , _seriesIndex = Just 1.0
          , _publisher = Just "Publisher"
          , _published = Nothing
          , _tags = ["tag1", "tag2"]
          , _rating = Just 4
          , _comments = Just "New comment"
          , _location = Nothing  -- Calibre doesn't know location
          , _custom = Map.fromList [("identifier:amazon", String "ASIN123")]
          , _added = testTime2
          , _modified = testTime2
          }
        existingBook = Book
          { _bookId = "42"
          , _isbn = Nothing  -- Was missing
          , _title = "Old Title"
          , _authors = ["Old Author"]
          , _series = Nothing
          , _seriesIndex = Nothing
          , _publisher = Nothing
          , _published = Nothing
          , _tags = []
          , _rating = Nothing
          , _comments = Nothing
          , _location = Just "Shelf A"  -- User set this
          , _custom = Map.fromList [("myfield", String "myvalue")]
          , _added = testTime1  -- Original add time
          , _modified = testTime1
          }

    it "preserves existing location" $ do
      let merged = mergeBooks calibreBook existingBook
      _location merged `shouldBe` Just "Shelf A"

    it "preserves existing added timestamp" $ do
      let merged = mergeBooks calibreBook existingBook
      _added merged `shouldBe` testTime1

    it "uses calibre data for title, authors, etc." $ do
      let merged = mergeBooks calibreBook existingBook
      _title merged `shouldBe` "Updated Title"
      _authors merged `shouldBe` ["New Author"]
      _isbn merged `shouldBe` Just "9780134685991"

    it "preserves non-identifier custom fields" $ do
      let merged = mergeBooks calibreBook existingBook
      Map.lookup "myfield" (_custom merged) `shouldBe` Just (String "myvalue")

    it "adds new identifier custom fields from calibre" $ do
      let merged = mergeBooks calibreBook existingBook
      Map.lookup "identifier:amazon" (_custom merged) `shouldBe` Just (String "ASIN123")

    it "keeps bookId from existing book" $ do
      let merged = mergeBooks calibreBook existingBook
      _bookId merged `shouldBe` "42"
      _bookId merged `shouldNotBe` "calibre-42"
