module Main (main) where

import Test.Hspec
import qualified TypesSpec
import qualified SearchSpec
import qualified BatchImportSpec
import qualified CalibreImportSpec
import qualified YamlSpec
import qualified NormalizeSpec
import qualified CommandBarSpec
import qualified GroupedListSpec
import qualified EnrichSpec

main :: IO ()
main = hspec $ do
  TypesSpec.spec
  SearchSpec.spec
  BatchImportSpec.spec
  CalibreImportSpec.spec
  YamlSpec.spec
  NormalizeSpec.spec
  CommandBarSpec.spec
  GroupedListSpec.spec
  EnrichSpec.spec
