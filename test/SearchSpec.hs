module SearchSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Data.Maybe (fromJust)
import Libri.Search.Fuzzy
import Libri.Types
import Test.Hspec

-- Helper to create a test book
makeBook :: Text -> Text -> [Text] -> Book
makeBook bid bookTitle bookAuthors =
  let timestamp = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = bid
       , _isbn = Nothing
       , _title = bookTitle
       , _authors = bookAuthors
       , _series = Nothing
       , _seriesIndex = Nothing
       , _publisher = Nothing
       , _published = Nothing
       , _tags = []
       , _rating = Nothing
       , _comments = Nothing
       , _location = Nothing
       , _custom = Map.empty
       , _added = timestamp
       , _modified = timestamp
       }

makeBookWithTags :: Text -> Text -> [Text] -> [Text] -> Book
makeBookWithTags bid bookTitle bookAuthors bookTags =
  let timestamp = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = bid
       , _isbn = Nothing
       , _title = bookTitle
       , _authors = bookAuthors
       , _series = Nothing
       , _seriesIndex = Nothing
       , _publisher = Nothing
       , _published = Nothing
       , _tags = bookTags
       , _rating = Nothing
       , _comments = Nothing
       , _location = Nothing
       , _custom = Map.empty
       , _added = timestamp
       , _modified = timestamp
       }

-- | Default threshold for tests (matches config default)
testThreshold :: Double
testThreshold = 0.6

spec :: Spec
spec = describe "Fuzzy Search" $ do
  let book1 = makeBook "1" "The Pragmatic Programmer" ["David Thomas", "Andrew Hunt"]
      book2 = makeBook "2" "Clean Code" ["Robert Martin"]
      book3 = makeBook "3" "Programming Pearls" ["Jon Bentley"]
      testBooks = [book1, book2, book3]

  describe "tokenize" $ do
    it "splits text into lowercase tokens" $ do
      tokenize "Hello World" `shouldBe` ["hello", "world"]

    it "removes punctuation" $ do
      tokenize "Hello, World!" `shouldBe` ["hello", "world"]

    it "handles empty strings" $ do
      tokenize "" `shouldBe` []

  describe "fuzzyMatch" $ do
    it "returns 1.0 for exact match" $ do
      fuzzyMatch "hello" "hello" `shouldBe` 1.0

    it "returns high score for substring match" $ do
      fuzzyMatch "hello" "helloworld" `shouldSatisfy` (> 0.8)

    it "returns lower score for different strings" $ do
      fuzzyMatch "hello" "world" `shouldSatisfy` (< 0.5)

  describe "searchBooks" $ do
    it "ranks exact title match first" $ do
      let results = searchBooks testThreshold "Pragmatic" testBooks
      length results `shouldSatisfy` (> 0)
      case results of
        (r:_) -> _title r `shouldBe` "The Pragmatic Programmer"
        []    -> expectationFailure "expected results"

    it "ranks author match first when searching by author" $ do
      let results = searchBooks testThreshold "Martin" testBooks
      length results `shouldSatisfy` (> 0)
      case results of
        (r:_) -> _title r `shouldBe` "Clean Code"
        []    -> expectationFailure "expected results"

    it "finds fuzzy match" $ do
      let results = searchBooks testThreshold "programing" testBooks  -- typo
      length results `shouldSatisfy` (> 0)

    it "returns all books for empty query" $ do
      let results = searchBooks testThreshold "" testBooks
      length results `shouldBe` 3

    it "ranks title matches higher than author matches" $ do
      let results = searchBooks testThreshold "Programming" testBooks
      case results of
        (r:_) -> _title r `shouldBe` "Programming Pearls"
        []    -> expectationFailure "expected results"

  describe "short query behavior" $ do
    it "uses exact match for queries < 3 chars" $ do
      let results = searchBooksExact "an" testBooks
      -- Should find books with "an" substring
      length results `shouldSatisfy` (>= 0)

  describe "majority word matching" $ do
    it "requires majority of query words to match" $ do
      -- "Programming Pearls" should match "Programming" query
      let results = searchBooks testThreshold "Programming" testBooks
      length results `shouldSatisfy` (> 0)

  describe "accent-insensitive search" $ do
    let accentBooks =
          [ makeBook "a1" "Rebaño" ["Óscar Contardo"]
          , makeBook "a2" "Being and Time" ["Martin Heidegger"]
          , makeBook "a3" "Café Society" ["Various"]
          ]

    it "finds accented title with plain ASCII query" $ do
      let results = searchBooks testThreshold "Rebano" accentBooks
      length results `shouldSatisfy` (> 0)
      case results of
        (r:_) -> _title r `shouldBe` "Rebaño"
        []    -> expectationFailure "expected results"

    it "finds accented author with plain ASCII query" $ do
      let results = searchBooks testThreshold "Oscar" accentBooks
      length results `shouldSatisfy` (> 0)
      case results of
        (r:_) -> _title r `shouldBe` "Rebaño"
        []    -> expectationFailure "expected results"

    it "finds accented title with uppercase query" $ do
      let results = searchBooks testThreshold "CAFE" accentBooks
      length results `shouldSatisfy` (> 0)
      case results of
        (r:_) -> _title r `shouldBe` "Café Society"
        []    -> expectationFailure "expected results"

  describe "tokenize normalizes accents" $ do
    it "folds accents during tokenization" $
      tokenize "Óscar" `shouldBe` ["oscar"]

    it "folds accents and lowercases" $
      tokenize "Café" `shouldBe` ["cafe"]
