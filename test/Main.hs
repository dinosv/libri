module Main (main) where

import Test.Hspec
import qualified TypesSpec
import qualified SearchSpec
import qualified BatchImportSpec
import qualified CalibreImportSpec
import qualified CalibreReconcileSpec
import qualified YamlSpec
import qualified NormalizeSpec
import qualified CommandBarSpec
import qualified GroupedListSpec
import qualified EnrichSpec
import qualified TagSidebarSpec
import qualified TagsSpec
import qualified DoctorSpec
import qualified MigrateSpec
import qualified AddBookSpec
import qualified CommandsSpec
import qualified CalibreSyncSpec
import qualified CalibreImportDriverSpec

main :: IO ()
main = hspec $ do
  TypesSpec.spec
  SearchSpec.spec
  BatchImportSpec.spec
  CalibreImportSpec.spec
  CalibreReconcileSpec.spec
  YamlSpec.spec
  NormalizeSpec.spec
  CommandBarSpec.spec
  GroupedListSpec.spec
  EnrichSpec.spec
  TagSidebarSpec.spec
  TagsSpec.spec
  DoctorSpec.spec
  MigrateSpec.spec
  AddBookSpec.spec
  CommandsSpec.spec
  CalibreSyncSpec.spec
  CalibreImportDriverSpec.spec
