module Main (main) where

import Test.Hspec
import qualified TypesSpec
import qualified SearchSpec
import qualified BatchImportSpec
import qualified CalibreImportSpec

main :: IO ()
main = hspec $ do
  TypesSpec.spec
  SearchSpec.spec
  BatchImportSpec.spec
  CalibreImportSpec.spec
