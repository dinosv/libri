module TagsSpec (spec) where

import Libri.CLI.Tags (renameTag, deleteTag, validTagName)
import Test.Hspec

spec :: Spec
spec = describe "Tags" $ do

  describe "validTagName" $ do
    it "rejects an empty or blank tag name" $ do
      validTagName "" `shouldBe` False
      validTagName "   " `shouldBe` False

    it "accepts a real tag name" $
      validTagName "Public Health" `shouldBe` True

  describe "renameTag" $ do
    it "renames a matching tag verbatim" $
      renameTag "Public health" "Public Health" ["Public health", "Arte"]
        `shouldBe` Just ["Public Health", "Arte"]

    it "matches case- and accent-insensitively" $
      renameTag "filosofia" "Filosofía" ["FILOSOFÍA", "Arte"]
        `shouldBe` Just ["Filosofía", "Arte"]

    it "merges when the new tag already exists" $
      renameTag "Public health" "Public Health" ["Public Health", "Public health"]
        `shouldBe` Just ["Public Health"]

    it "returns Nothing when the old tag is absent" $
      renameTag "History" "Historia" ["Arte"] `shouldBe` Nothing

    it "returns Nothing when nothing changes" $
      renameTag "Arte" "Arte" ["Arte"] `shouldBe` Nothing

    it "preserves order of unaffected tags" $
      renameTag "b" "B2" ["a", "b", "c"] `shouldBe` Just ["a", "B2", "c"]

  describe "deleteTag" $ do
    it "removes all spellings of the tag" $
      deleteTag "arte" ["Arte", "ARTE", "Historia"] `shouldBe` Just ["Historia"]

    it "returns Nothing when the tag is absent" $
      deleteTag "Missing" ["Arte"] `shouldBe` Nothing

    it "can empty the tag list" $
      deleteTag "Arte" ["Arte"] `shouldBe` Just []
