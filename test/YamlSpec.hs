module YamlSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Aeson (Value(..))
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Libri.Storage.Yaml (saveBook, deleteBook, loadBook, loadBooksWithErrors, loadConfig, initDataDir)
import Libri.Types (Book(..), Config(..), LibriError(..), bookFilename, legacyBookFilename, defaultConfig)
import System.Directory (listDirectory, renameFile)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

spec :: Spec
spec = describe "YAML Storage" $ do

  describe "loadConfig" $ do
    it "fails when a required config file is missing" $
      withSystemTempDirectory "libri-test" $ \dir -> do
        let path = dir </> "typo.yaml"
        result <- loadConfig True path
        result `shouldBe` Left (FileNotFound path)

    it "falls back to defaults when an optional config file is missing" $
      withSystemTempDirectory "libri-test" $ \dir -> do
        result <- loadConfig False (dir </> "config.yaml")
        result `shouldBe` Right defaultConfig

  describe "initDataDir" $ do
    it "reports when it creates a new library, and not afterwards" $
      withSystemTempDirectory "libri-test" $ \dir -> do
        let cfg = defaultConfig { _dataDir = dir </> "data" }
        initDataDir cfg `shouldReturn` True
        initDataDir cfg `shouldReturn` False

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

    it "saving replaces a legacy-named file with the canonical name" $
      withSystemTempDirectory "libri-test" $ \dir -> do
        let cfg = defaultConfig { _dataDir = dir }
            booksDir = dir </> "books"
        Right () <- saveBook cfg sampleBook
        -- Simulate a pre-slug file name
        renameFile (booksDir </> bookFilename sampleBook)
                   (booksDir </> legacyBookFilename sampleBook)
        Right () <- saveBook cfg sampleBook
        files <- listDirectory booksDir
        files `shouldBe` [bookFilename sampleBook]

    it "saving after a title change renames the file" $
      withSystemTempDirectory "libri-test" $ \dir -> do
        let cfg = defaultConfig { _dataDir = dir }
            booksDir = dir </> "books"
            renamed = sampleBook { _title = "A Different Title" }
        Right () <- saveBook cfg sampleBook
        Right () <- saveBook cfg renamed
        files <- listDirectory booksDir
        files `shouldBe` [bookFilename renamed]

    it "deleteBook removes a legacy-named file" $
      withSystemTempDirectory "libri-test" $ \dir -> do
        let cfg = defaultConfig { _dataDir = dir }
            booksDir = dir </> "books"
        Right () <- saveBook cfg sampleBook
        renameFile (booksDir </> bookFilename sampleBook)
                   (booksDir </> legacyBookFilename sampleBook)
        Right () <- deleteBook cfg sampleBook
        files <- listDirectory booksDir
        files `shouldBe` []

    it "loadBooksWithErrors skips corrupt files but loads the rest" $
      withSystemTempDirectory "libri-test" $ \dir -> do
        let cfg = defaultConfig { _dataDir = dir }
        saveResult <- saveBook cfg sampleBook
        saveResult `shouldBe` Right ()
        writeFile (dir </> "books" </> "corrupt.yaml") "{ not: [valid yaml"
        (errs, bks) <- loadBooksWithErrors cfg
        length errs `shouldBe` 1
        map _bookId bks `shouldBe` [_bookId sampleBook]
