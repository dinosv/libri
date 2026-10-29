module CalibreSyncSpec (spec) where

import Data.Aeson (Value(..))
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Libri.Storage.CalibreSync
import Libri.Types (Book(..))
import Test.Hspec

b :: Book
b = Book
  { _bookId = "b1"
  , _isbn = Just "9780000000001"
  , _title = "Historia del arte"
  , _authors = ["A", "B"]
  , _series = Nothing
  , _seriesIndex = Just 2
  , _publisher = Just "Jones"
  , _published = Just (fromGregorian 2010 1 1)
  , _tags = ["Arte", "Historia"]
  , _rating = Just 4
  , _comments = Nothing
  , _location = Nothing
  , _custom = Map.empty
  , _added = UTCTime (fromGregorian 2025 1 1) 0
  , _modified = UTCTime (fromGregorian 2025 1 1) 0
  }

spec :: Spec
spec = describe "Calibre field fingerprints" $ do
  it "pins the FNV-1a test vectors" $ do
    fnv1a64Hex "" `shouldBe` "cbf29ce484222325"
    fnv1a64Hex "a" `shouldBe` "af63dc4c8601ec8c"

  it "fingerprints all eleven fields with 16 hex digits" $ do
    let ps = fieldPrints b
    Map.keys ps `shouldBe` [minBound .. maxBound]
    map T.length (Map.elems ps) `shouldSatisfy` all (== 16)

  it "names fields by their stable keys" $
    map fieldKey [minBound .. maxBound] `shouldBe`
      [ "title", "authors", "series", "seriesIndex", "publisher", "published"
      , "isbn", "tags", "rating", "comments", "identifiers" ]

  it "ignores tag order" $
    fieldPrints b { _tags = ["Arte", "Historia"] } Map.! FTags
      `shouldBe` fieldPrints b { _tags = ["Historia", "Arte"] } Map.! FTags

  it "ignores identifier order and the calibre provenance key" $ do
    let ids1 = Map.fromList
          [ ("identifier:isbn", String "1"), ("identifier:doi", String "2") ]
        ids2 = Map.fromList
          [ ("identifier:doi", String "2"), ("identifier:calibre", String "9")
          , ("identifier:isbn", String "1"), ("other", String "x") ]
    calibreIdentifiers b { _custom = ids2 } `shouldBe` ids1
    fieldPrints b { _custom = ids1 } Map.! FIdentifiers
      `shouldBe` fieldPrints b { _custom = ids2 } Map.! FIdentifiers

  it "detects a changed identifier value" $
    fieldPrints b { _custom = Map.fromList [("identifier:isbn", String "1")] } Map.! FIdentifiers
      `shouldNotBe`
      fieldPrints b { _custom = Map.fromList [("identifier:isbn", String "2")] } Map.! FIdentifiers

  it "distinguishes no publisher from an empty publisher" $
    fieldPrints b { _publisher = Nothing } Map.! FPublisher
      `shouldNotBe` fieldPrints b { _publisher = Just "" } Map.! FPublisher

  it "keeps author order significant" $
    fieldPrints b { _authors = ["A", "B"] } Map.! FAuthors
      `shouldNotBe` fieldPrints b { _authors = ["B", "A"] } Map.! FAuthors

  it "renders canonical text per the rules" $ do
    fieldCanonical FAuthors b `shouldBe` "A\USB"
    fieldCanonical FTags b `shouldBe` "Arte\USHistoria"
    fieldCanonical FSeries b `shouldBe` "-"
    fieldCanonical FPublisher b `shouldBe` "+Jones"
