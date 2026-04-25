module EnrichSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Libri.CLI.Enrich (needsEnrichment, mergeTags)
import Libri.Types (Book(..))
import Test.Hspec

mkBook :: Text -> Maybe Text -> [Text] -> Maybe Text -> Book
mkBook bookTitle bookIsbn bookTags bookComments =
  let ts = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = "1"
       , _isbn = bookIsbn
       , _title = bookTitle
       , _authors = ["Author"]
       , _series = Nothing
       , _seriesIndex = Nothing
       , _publisher = Nothing
       , _published = Nothing
       , _tags = bookTags
       , _rating = Nothing
       , _comments = bookComments
       , _location = Nothing
       , _custom = Map.empty
       , _added = ts
       , _modified = ts
       }

spec :: Spec
spec = describe "Enrich" $ do

  describe "needsEnrichment" $ do
    it "returns True for book with no tags and no comments" $
      needsEnrichment (mkBook "Test" (Just "123") [] Nothing) `shouldBe` True

    it "returns True for book with tags but no comments" $
      needsEnrichment (mkBook "Test" (Just "123") ["Fiction"] Nothing) `shouldBe` True

    it "returns True for book with comments but no tags" $
      needsEnrichment (mkBook "Test" (Just "123") [] (Just "A description")) `shouldBe` True

    it "returns False for book with both tags and comments" $
      needsEnrichment (mkBook "Test" (Just "123") ["Fiction"] (Just "A description")) `shouldBe` False

    it "returns False for book without ISBN" $
      needsEnrichment (mkBook "Test" Nothing [] Nothing) `shouldBe` False

  describe "mergeTags" $ do
    it "adds new tags to empty list" $
      mergeTags [] ["Fiction", "History"] `shouldBe` ["Fiction", "History"]

    it "deduplicates case-insensitively" $
      mergeTags ["fiction"] ["Fiction", "History"] `shouldBe` ["fiction", "History"]

    it "deduplicates accent-insensitively" $
      mergeTags ["Filosofía"] ["Filosofia", "History"] `shouldBe` ["Filosofía", "History"]

    it "caps new tags at 10" $ do
      let newTags = map (\n -> "Tag" <> (if n < 10 then "0" else "") <> T.pack (show n))
                        ([1..15] :: [Int])
      length (mergeTags [] newTags) `shouldBe` 10

    it "preserves existing tags and adds up to 10 new" $ do
      let existing = ["A", "B"]
          newTags = map (\n -> "Tag" <> T.pack (show n)) ([1..15] :: [Int])
      length (mergeTags existing newTags) `shouldBe` 12

    it "returns existing when no new tags" $
      mergeTags ["Fiction"] [] `shouldBe` ["Fiction"]
