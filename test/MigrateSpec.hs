module MigrateSpec (spec) where

import Data.Aeson (Value (..))
import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Libri.CLI.Migrate (planMigration, migrateBook)
import Libri.Types
import Test.Hspec

mkBook :: Text -> Text -> Book
mkBook bid bookTitle =
  let ts = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = bid
       , _isbn = Nothing
       , _title = bookTitle
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
       , _added = ts
       , _modified = ts
       }

uuid1 :: Text
uuid1 = "3fa2c1d0-1111-4222-8333-444455556666"

spec :: Spec
spec = describe "Migrate" $ do

  describe "migrateBook" $ do
    it "assigns the new UUID and keeps the old id as provenance" $ do
      let b = migrateBook uuid1 (mkBook "100" "A Title")
      _bookId b `shouldBe` uuid1
      Map.lookup "identifier:calibre" (_custom b) `shouldBe` Just (String "100")

    it "leaves a book that already has a UUID id unchanged" $ do
      let orig = mkBook uuid1 "A Title"
      migrateBook "ffffffff-0000-4000-8000-000000000000" orig `shouldBe` orig

    it "does not overwrite an existing calibre identifier" $ do
      let orig = (mkBook "100" "A Title")
            { _custom = Map.fromList [("identifier:calibre", String "lib:100")] }
          b = migrateBook uuid1 orig
      Map.lookup "identifier:calibre" (_custom b) `shouldBe` Just (String "lib:100")

    it "preserves the modified timestamp" $ do
      let orig = mkBook "100" "A Title"
      _modified (migrateBook uuid1 orig) `shouldBe` _modified orig

  describe "planMigration" $ do
    it "selects books with non-UUID ids" $ do
      let b = mkBook "100" "A Title"
      map (_bookId . snd) (planMigration [("books/100.yaml", b)])
        `shouldBe` ["100"]

    it "selects UUID books whose filename is stale" $ do
      let b = mkBook uuid1 "A Title"
      length (planMigration [("books/old-name.yaml", b)]) `shouldBe` 1

    it "skips UUID books with canonical filenames" $ do
      let b = mkBook uuid1 "A Title"
      planMigration [("books/" <> bookFilename b, b)] `shouldBe` []
