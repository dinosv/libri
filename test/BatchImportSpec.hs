module BatchImportSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Libri.CLI.BatchImport (parseIsbnFile, FetchResult(..), BatchResults(..), categorizeResults, ImportChoice(..), parseImportChoice)
import Libri.Types (Book(..))
import Test.Hspec

spec :: Spec
spec = describe "Batch ISBN Import" $ do

  describe "parseImportChoice" $ do
    it "accepts the listed choices, ignoring case and spaces" $ do
      parseImportChoice "a" `shouldBe` Just ImportNew
      parseImportChoice " D " `shouldBe` Just ImportAll
      parseImportChoice "s" `shouldBe` Just ImportSelect
      parseImportChoice "n" `shouldBe` Just ImportCancel

    it "does not treat an empty or unknown answer as import" $ do
      parseImportChoice "" `shouldBe` Nothing
      parseImportChoice "no" `shouldBe` Nothing
      parseImportChoice "q" `shouldBe` Nothing

  describe "parseIsbnFile" $ do
    it "parses one ISBN per line" $ do
      parseIsbnFile "978-0-13-468599-1\n978-0-596-51774-8"
        `shouldBe` ["978-0-13-468599-1", "978-0-596-51774-8"]

    it "skips empty lines" $ do
      parseIsbnFile "978-0-13-468599-1\n\n978-0-596-51774-8"
        `shouldBe` ["978-0-13-468599-1", "978-0-596-51774-8"]

    it "skips comment lines starting with #" $ do
      parseIsbnFile "# My books\n978-0-13-468599-1\n# Another comment\n978-0-596-51774-8"
        `shouldBe` ["978-0-13-468599-1", "978-0-596-51774-8"]

    it "trims whitespace from ISBNs" $ do
      parseIsbnFile "  978-0-13-468599-1  \n\t978-0-596-51774-8\t"
        `shouldBe` ["978-0-13-468599-1", "978-0-596-51774-8"]

    it "returns empty list for empty file" $ do
      parseIsbnFile "" `shouldBe` []

    it "returns empty list for file with only comments" $ do
      parseIsbnFile "# Comment 1\n# Comment 2" `shouldBe` []

    it "handles single ISBN" $ do
      parseIsbnFile "978-0-13-468599-1" `shouldBe` ["978-0-13-468599-1"]

    it "handles Windows line endings (CRLF)" $ do
      parseIsbnFile "978-0-13-468599-1\r\n978-0-596-51774-8"
        `shouldBe` ["978-0-13-468599-1", "978-0-596-51774-8"]

  describe "categorizeResults" $ do
    let testTime = UTCTime (fromGregorian 2025 1 1) 0
        mkBook bookId isbnVal titleVal = Book
          { _bookId = bookId
          , _isbn = Just isbnVal
          , _title = titleVal
          , _authors = ["Author"]
          , _series = Nothing
          , _seriesIndex = Nothing
          , _publisher = Nothing
          , _published = Nothing
          , _tags = []
          , _rating = Nothing
          , _comments = Nothing
          , _location = Nothing
          , _custom = Map.empty
          , _added = testTime
          , _modified = testTime
          }
        book1 = mkBook "id1" "978-0-13-468599-1" "Book 1"
        book2 = mkBook "id2" "978-0-596-51774-8" "Book 2"
        existingBook = mkBook "existing" "978-0-13-468599-1" "Existing Book"

    it "separates successful fetches into brNew" $ do
      let results = [FetchSuccess book1, FetchSuccess book2]
          categorized = categorizeResults results
      brNew categorized `shouldBe` [book1, book2]
      brDuplicates categorized `shouldBe` []
      brNotFound categorized `shouldBe` []
      brErrors categorized `shouldBe` []

    it "separates not found ISBNs into brNotFound" $ do
      let results = [FetchNotFound "978-0-00-000000-0", FetchNotFound "978-1-11-111111-1"]
          categorized = categorizeResults results
      brNew categorized `shouldBe` []
      brNotFound categorized `shouldBe` ["978-0-00-000000-0", "978-1-11-111111-1"]

    it "separates errors into brErrors" $ do
      let results = [FetchError "978-0-00-000000-0" "Network timeout"]
          categorized = categorizeResults results
      brNew categorized `shouldBe` []
      brErrors categorized `shouldBe` [("978-0-00-000000-0", "Network timeout")]

    it "separates duplicates into brDuplicates" $ do
      let results = [FetchDuplicate book1 existingBook]
          categorized = categorizeResults results
      brNew categorized `shouldBe` []
      brDuplicates categorized `shouldBe` [(book1, existingBook)]

    it "correctly categorizes mixed results" $ do
      let results =
            [ FetchSuccess book1
            , FetchDuplicate book2 existingBook
            , FetchNotFound "978-0-00-000000-0"
            , FetchError "978-1-11-111111-1" "API error"
            ]
          categorized = categorizeResults results
      brNew categorized `shouldBe` [book1]
      brDuplicates categorized `shouldBe` [(book2, existingBook)]
      brNotFound categorized `shouldBe` ["978-0-00-000000-0"]
      brErrors categorized `shouldBe` [("978-1-11-111111-1", "API error")]

    it "returns empty BatchResults for empty input" $ do
      let categorized = categorizeResults []
      brNew categorized `shouldBe` []
      brDuplicates categorized `shouldBe` []
      brNotFound categorized `shouldBe` []
      brErrors categorized `shouldBe` []
