module NormalizeSpec (spec) where

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
