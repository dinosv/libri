module CalibreImportSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Libri.Storage.CalibreImport (extractIsbn, partitionIdentifiers)
import Test.Hspec

spec :: Spec
spec = describe "Calibre Import" $ do

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
