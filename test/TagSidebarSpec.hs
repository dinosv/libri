module TagSidebarSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Libri.TUI.Views.TagSidebar
import Libri.Types
import Test.Hspec

makeBook :: Text -> [Text] -> Book
makeBook bid bookTags =
  let timestamp = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = bid
       , _isbn = Nothing
       , _title = "Book " <> bid
       , _authors = ["Author"]
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
spec = describe "TagSidebar" $ do
  let book1 = makeBook "1" ["Filosofía", "Historia"]
      book2 = makeBook "2" ["Arte"]
      book3 = makeBook "3" ["filosofía y más"]
      book4 = makeBook "4" []
      testBooks = [book1, book2, book3, book4]

  describe "buildTagEntries" $ do
    it "starts with All carrying the collection size" $ do
      case buildTagEntries testBooks of
        (AllBooks n : _) -> n `shouldBe` 4
        other -> expectationFailure ("unexpected head: " <> show other)

    it "orders tags alphabetically with accents folded" $ do
      let names = [t | TagEntry t _ <- buildTagEntries testBooks]
      names `shouldBe` ["Arte", "Filosofía", "filosofía y más", "Historia"]

    it "counts books per tag" $ do
      let counts = Map.fromList [(t, n) | TagEntry t n <- buildTagEntries testBooks]
      Map.lookup "Filosofía" counts `shouldBe` Just 1
      Map.lookup "Arte" counts `shouldBe` Just 1

    it "does not double-count a duplicated tag within one book" $ do
      let dup = makeBook "5" ["Arte", "Arte"]
          counts = Map.fromList [(t, n) | TagEntry t n <- buildTagEntries [dup]]
      Map.lookup "Arte" counts `shouldBe` Just 1

    it "ends with Untagged when tagless books exist" $ do
      case reverse (buildTagEntries testBooks) of
        (Untagged n : _) -> n `shouldBe` 1
        other -> expectationFailure ("unexpected last: " <> show other)

    it "omits Untagged when every book has tags" $ do
      let entries = buildTagEntries [book1, book2]
      [n | Untagged n <- entries] `shouldBe` []

    it "handles an empty library" $ do
      buildTagEntries [] `shouldBe` [AllBooks 0]

  describe "entryToFilter" $ do
    it "maps All to no filter" $
      entryToFilter (AllBooks 3) `shouldBe` Nothing

    it "maps a tag to an exact filter" $
      entryToFilter (TagEntry "Arte" 2) `shouldBe` Just (FilterTagExact "Arte")

    it "maps Untagged to the untagged filter" $
      entryToFilter (Untagged 1) `shouldBe` Just FilterUntagged

  describe "matchesFilter" $ do
    it "FilterTagExact does not match tag supersets" $ do
      matchesFilter (FilterTagExact "Filosofía") book1 `shouldBe` True
      matchesFilter (FilterTagExact "Filosofía") book3 `shouldBe` False

    it "FilterTagExact matches accent- and case-insensitively" $ do
      matchesFilter (FilterTagExact "filosofia") book1 `shouldBe` True

    it "FilterUntagged matches only tagless books" $ do
      matchesFilter FilterUntagged book4 `shouldBe` True
      matchesFilter FilterUntagged book1 `shouldBe` False

    it "FilterTag still matches by substring" $ do
      matchesFilter (FilterTag "filosofia") book3 `shouldBe` True
