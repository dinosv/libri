module CalibreImportSpec (spec) where

import Data.Aeson (Value (..))
import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Libri.Storage.CalibreImport (extractIsbn, partitionIdentifiers, calibreIdentifier, findExistingBook)
import Libri.Types
import Test.Hspec

mkBook :: Text -> Maybe Text -> Map.Map Text Value -> Book
mkBook bid bookIsbn customFields =
  let ts = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = bid
       , _isbn = bookIsbn
       , _title = "Book " <> bid
       , _authors = []
       , _series = Nothing
       , _seriesIndex = Nothing
       , _publisher = Nothing
       , _published = Nothing
       , _tags = []
       , _rating = Nothing
       , _comments = Nothing
       , _location = Nothing
       , _custom = customFields
       , _added = ts
       , _modified = ts
       }

spec :: Spec
spec = describe "Calibre Import" $ do

  describe "findExistingBook" $ do
    let libUuid = "lib-uuid-1"
        calRef n = calibreIdentifier libUuid n
        imported = mkBook "new-uuid" (Just "9780134685991")
          (Map.fromList [("identifier:calibre", String (calRef 100))])

    it "matches by namespaced calibre identifier" $ do
      let existing = mkBook "old-uuid" Nothing
            (Map.fromList [("identifier:calibre", String (calRef 100))])
      _bookId <$> findExistingBook [existing] imported `shouldBe` Just "old-uuid"

    it "matches a migrated book by bare calibre id" $ do
      let existing = mkBook "old-uuid" Nothing
            (Map.fromList [("identifier:calibre", String "100")])
      _bookId <$> findExistingBook [existing] imported `shouldBe` Just "old-uuid"

    it "matches by normalised ISBN when no calibre identifier" $ do
      let existing = mkBook "old-uuid" (Just "978-0-13-468599-1") Map.empty
      _bookId <$> findExistingBook [existing] imported `shouldBe` Just "old-uuid"

    it "matches a legacy book whose id is the calibre number" $ do
      let existing = mkBook "100" Nothing Map.empty
      _bookId <$> findExistingBook [existing] imported `shouldBe` Just "100"

    it "does not match a book from a different calibre library" $ do
      let otherRef = calibreIdentifier "lib-uuid-2" 100
          existing = mkBook "other-uuid" (Just "9999999999999")
            (Map.fromList [("identifier:calibre", String otherRef)])
      findExistingBook [existing] imported `shouldBe` Nothing

    it "returns Nothing when there is no match" $ do
      findExistingBook [] imported `shouldBe` Nothing

  describe "extractIsbn" $ do
    it "returns Nothing for empty list" $ do
      extractIsbn [] `shouldBe` Nothing

    it "prefers ISBN-13 over ISBN-10" $ do
      extractIsbn [("isbn", "0134685991"), ("isbn", "9780134685991")]
        `shouldBe` Just "9780134685991"

    it "returns ISBN-13 when only ISBN-13 present" $ do
      extractIsbn [("isbn", "9780134685991")]
        `shouldBe` Just "9780134685991"

    it "returns ISBN-10 when only ISBN-10 present" $ do
      extractIsbn [("isbn", "0134685991")]
        `shouldBe` Just "0134685991"

    it "ignores non-isbn identifiers" $ do
      extractIsbn [("amazon", "B07N1XLQ7D"), ("google", "abc123")]
        `shouldBe` Nothing

  describe "partitionIdentifiers" $ do
    it "separates isbn from other identifiers" $ do
      let ids = [("isbn", "9780134685991"), ("amazon", "B07N1XLQ7D")]
          (maybeIsbn, others) = partitionIdentifiers ids
      maybeIsbn `shouldBe` Just "9780134685991"
      others `shouldBe` Map.fromList [("identifier:amazon", "B07N1XLQ7D")]

    it "prefixes all non-isbn identifiers with identifier:" $ do
      let ids = [("amazon", "B07N1XLQ7D"), ("google", "abc123"), ("goodreads", "12345")]
          (_, others) = partitionIdentifiers ids
      Map.keys others `shouldMatchList`
        ["identifier:amazon", "identifier:google", "identifier:goodreads"]

    it "handles empty identifier list" $ do
      let (maybeIsbn, others) = partitionIdentifiers []
      maybeIsbn `shouldBe` Nothing
      others `shouldBe` Map.empty

    it "handles multiple isbn entries by preferring ISBN-13" $ do
      let ids = [("isbn", "0134685991"), ("isbn", "9780134685991"), ("amazon", "B07N")]
          (maybeIsbn, others) = partitionIdentifiers ids
      maybeIsbn `shouldBe` Just "9780134685991"
      Map.lookup "identifier:amazon" others `shouldBe` Just "B07N"
