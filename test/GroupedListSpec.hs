module GroupedListSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Libri.TUI.Views.GroupedList
import Libri.Types
import Test.Hspec

makeBook :: Text -> Text -> [Text] -> [Text] -> Book
makeBook bid bookTitle bookAuthors bookTags =
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

spec :: Spec
spec = describe "GroupedList" $ do
  let book1 = makeBook "1" "Being and Time" ["Heidegger"] ["Philosophy"]
      book2 = makeBook "2" "Rebaño" ["Contardo"] ["History", "Religion"]
      book3 = makeBook "3" "The Visual Display" ["Tufte"] ["Art"]
      book4 = makeBook "4" "Untitled" ["Unknown"] []
      testBooks = [book1, book2, book3, book4]

  describe "buildGroupedList" $ do
    it "groups books by tag with section headers" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          headers = [t | SectionHeader t _ <- items]
      headers `shouldSatisfy` elem "Art"
      headers `shouldSatisfy` elem "History"
      headers `shouldSatisfy` elem "Philosophy"
      headers `shouldSatisfy` elem "Religion"
      headers `shouldSatisfy` elem "(Untagged)"

    it "puts untagged books at the end" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          lastHeader = last [t | SectionHeader t _ <- items]
      lastHeader `shouldBe` "(Untagged)"

    it "shows correct count in headers" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          artHeader = [(t, n) | SectionHeader t n <- items, t == "Art"]
      artHeader `shouldBe` [("Art", 1)]

    it "duplicates books with multiple tags" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          bookRows = [b | BookRow b <- items]
      length bookRows `shouldSatisfy` (> length testBooks)

    it "groups books by author" $ do
      let items = buildGroupedList GroupByAuthor SortByTitle Ascending testBooks
          headers = [t | SectionHeader t _ <- items]
      headers `shouldSatisfy` elem "Heidegger"
      headers `shouldSatisfy` elem "Contardo"

    it "sorts sections alphabetically" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          headers = [t | SectionHeader t _ <- items, t /= "(Untagged)"]
      headers `shouldBe` ["Art", "History", "Philosophy", "Religion"]

    it "returns an empty list for an empty library" $ do
      buildGroupedList GroupByTag SortByTitle Ascending [] `shouldBe` []
      buildGroupedList GroupByAuthor SortByTitle Ascending [] `shouldBe` []

    it "keeps a tag literally named like the author sentinel" $ do
      let oddBook = makeBook "5" "Odd" ["Someone"] ["(Unknown)"]
          items = buildGroupedList GroupByTag SortByTitle Ascending [oddBook]
          headers = [t | SectionHeader t _ <- items]
      headers `shouldBe` ["(Unknown)"]

    it "lastSelectableIndex finds the last book row" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
      lastSelectableIndex items `shouldBe` (length items - 1)

  describe "navigation" $ do
    it "nextSelectableIndex skips headers" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  , SectionHeader "Philosophy" 1
                  , BookRow book1
                  ]
      nextSelectableIndex items 1 `shouldBe` 3

    it "prevSelectableIndex skips headers" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  , SectionHeader "Philosophy" 1
                  , BookRow book1
                  ]
      prevSelectableIndex items 3 `shouldBe` 1

    it "nextSelectableIndex stays at last book" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  ]
      nextSelectableIndex items 1 `shouldBe` 1

    it "prevSelectableIndex stays at first book" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  ]
      prevSelectableIndex items 1 `shouldBe` 1

    it "firstSelectableIndex finds first book row" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  , SectionHeader "Philosophy" 1
                  , BookRow book1
                  ]
      firstSelectableIndex items `shouldBe` 1
