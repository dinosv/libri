module YamlSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Aeson (Value(..))
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Libri.Storage.Yaml (mergeBooks, saveBook, loadBook, loadBooksWithErrors)
import Libri.Types (Book(..), Config(..), bookFilename, defaultConfig)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
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

  describe "persistence round-trip" $ do
    let testTime = UTCTime (fromGregorian 2025 3 1) 0
        sampleBook = Book
          { _bookId = "rt-1"
          , _isbn = Just "9780134685991"
          , _title = "Round Trip"
          , _authors = ["Ada Author", "Bob Writer"]
          , _series = Just "A Series"
          , _seriesIndex = Just 2.5
          , _publisher = Just "Pub"
          , _published = Just (fromGregorian 2020 6 15)
          , _tags = ["tag1", "tag2"]
          , _rating = Just 4
          , _comments = Just "Some notes"
          , _location = Just "Shelf A"
          , _custom = Map.fromList [("myfield", String "v"), ("count", Number 3)]
          , _added = testTime
          , _modified = testTime
          }

    it "saveBook then loadBook preserves every field except modified" $
      withSystemTempDirectory "libri-test" $ \dir -> do
        let cfg = defaultConfig { _dataDir = dir }
        saveResult <- saveBook cfg sampleBook
        saveResult `shouldBe` Right ()
        loaded <- loadBook (dir </> "books" </> bookFilename sampleBook)
        case loaded of
          Left err -> expectationFailure (show err)
          Right b -> do
            _bookId b `shouldBe` _bookId sampleBook
            _isbn b `shouldBe` _isbn sampleBook
            _title b `shouldBe` _title sampleBook
            _authors b `shouldBe` _authors sampleBook
            _series b `shouldBe` _series sampleBook
            _seriesIndex b `shouldBe` _seriesIndex sampleBook
            _publisher b `shouldBe` _publisher sampleBook
            _published b `shouldBe` _published sampleBook
            _tags b `shouldBe` _tags sampleBook
            _rating b `shouldBe` _rating sampleBook
            _comments b `shouldBe` _comments sampleBook
            _location b `shouldBe` _location sampleBook
            _custom b `shouldBe` _custom sampleBook
            _added b `shouldBe` _added sampleBook

    it "loadBooksWithErrors skips corrupt files but loads the rest" $
      withSystemTempDirectory "libri-test" $ \dir -> do
        let cfg = defaultConfig { _dataDir = dir }
        saveResult <- saveBook cfg sampleBook
        saveResult `shouldBe` Right ()
        writeFile (dir </> "books" </> "corrupt.yaml") "{ not: [valid yaml"
        (errs, bks) <- loadBooksWithErrors cfg
        length errs `shouldBe` 1
        map _bookId bks `shouldBe` [_bookId sampleBook]
