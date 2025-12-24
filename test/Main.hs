module Main (main) where

import Test.Hspec
import qualified TypesSpec
import qualified SearchSpec
import qualified BatchImportSpec

main :: IO ()
main = hspec $ do
  TypesSpec.spec
  SearchSpec.spec
  BatchImportSpec.spec
