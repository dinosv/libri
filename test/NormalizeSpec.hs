module NormalizeSpec (spec) where

import qualified Data.Text as T
import Libri.Text.Normalize
import Test.Hspec

spec :: Spec
spec = describe "Text.Normalize" $ do
  describe "foldAccents" $ do
    it "strips acute accents" $
      foldAccents "Óscar" `shouldBe` "Oscar"
    it "strips grave accents" $
      foldAccents "è" `shouldBe` "e"
    it "strips circumflex" $
      foldAccents "café" `shouldBe` "cafe"
    it "strips tilde from n" $
      foldAccents "niño" `shouldBe` "nino"
    it "strips diaeresis" $
      foldAccents "über" `shouldBe` "uber"
    it "leaves ASCII unchanged" $
      foldAccents "hello" `shouldBe` "hello"
    it "leaves numbers unchanged" $
      foldAccents "2024" `shouldBe` "2024"
    it "handles empty string" $
      foldAccents "" `shouldBe` ""

  describe "normalizeText" $ do
    it "lowercases and folds accents" $
      normalizeText "ÓSCAR" `shouldBe` "oscar"
    it "lowercases plain ASCII" $
      normalizeText "Hello World" `shouldBe` "hello world"
    it "combines lowercase and accent folding" $
      normalizeText "Café Über" `shouldBe` "cafe uber"

  describe "slugify" $ do
    it "folds accents and lowercases" $
      slugify "Rebaño" `shouldBe` "rebano"
    it "replaces spaces and punctuation with single hyphens" $
      slugify "El Quijote: 2ª edición (1605)" `shouldBe` "el-quijote-2-edicion-1605"
    it "collapses runs of separators" $
      slugify "a --- b" `shouldBe` "a-b"
    it "trims leading and trailing separators" $
      slugify "¿Qué hacer?" `shouldBe` "que-hacer"
    it "caps length at 40 characters" $ do
      let s = slugify "This is an extremely long book title that goes on and on forever"
      s `shouldSatisfy` ((<= 40) . T.length)
    it "falls back to 'book' for empty titles" $
      slugify "" `shouldBe` "book"
    it "falls back to 'book' for punctuation-only titles" $
      slugify "!!!" `shouldBe` "book"
