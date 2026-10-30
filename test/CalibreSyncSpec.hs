module CalibreSyncSpec (spec) where

import Data.Aeson (Value(..))
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import qualified Data.Text.IO as TIO
import Libri.Storage.CalibreSync
import Libri.Types (LibriError(..), defaultConfig, Config(..))
import System.Directory (createDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
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
spec = do
  fingerprintSpec
  syncSpec

fingerprintSpec :: Spec
fingerprintSpec = describe "Calibre field fingerprints" $ do
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


sampleState :: SyncState
sampleState = SyncState $ Map.fromList
  [ ("lib-A", LibrarySync
      { lsPath = "/path/to/Calibre Library"
      , lsHome = HomeYes
      , lsBooks = Map.fromList
          [ ("lib-A:46", SyncMapped "book-uuid" (fieldPrints b))
          , ("lib-A:47", SyncIgnored)
          , ("lib-A:48", SyncPending)
          ]
      })
  , ("lib-B", LibrarySync "/other" HomeUnanswered Map.empty)
  , ("lib-C", LibrarySync "/before-rebuild" HomeFormer Map.empty)
  ]

syncSpec :: Spec
syncSpec = describe "Calibre sync state" $ do
  it "round-trips through save and load" $
    withSystemTempDirectory "libri-sync" $ \dir -> do
      let cfg = defaultConfig { _dataDir = dir }
      saveSyncState cfg sampleState `shouldReturn` Right ()
      loadSyncState cfg `shouldReturn` Right sampleState

  it "loads a missing file as the empty state" $
    withSystemTempDirectory "libri-sync" $ \dir ->
      loadSyncState (defaultConfig { _dataDir = dir }) `shouldReturn` Right emptySyncState

  it "reports a malformed file without touching it" $
    withSystemTempDirectory "libri-sync" $ \dir -> do
      let cfg = defaultConfig { _dataDir = dir }
          path = dir </> "calibre-sync.yaml"
          bytes = "libraries: [oops"
      TIO.writeFile path bytes
      r <- loadSyncState cfg
      case r of
        Left (ParseError p _) -> p `shouldBe` path
        other -> expectationFailure ("expected ParseError, got " <> show other)
      TIO.readFile path `shouldReturn` bytes

  it "reports a failed save as a write error" $
    withSystemTempDirectory "libri-sync" $ \dir -> do
      let path = dir </> "calibre-sync.yaml"
      createDirectory path
      r <- saveSyncState (defaultConfig { _dataDir = dir }) sampleState
      case r of
        Left (WriteError p _) -> p `shouldBe` path
        other -> expectationFailure ("expected WriteError, got " <> show other)

  it "accepts an unquoted yes/no for home" $
    withSystemTempDirectory "libri-sync" $ \dir -> do
      let cfg = defaultConfig { _dataDir = dir }
      TIO.writeFile (dir </> "calibre-sync.yaml") $ T.intercalate "\n"
        [ "libraries:", "  A:", "    path: /a", "    home: yes", "    books: {}"
        , "  B:", "    path: /b", "    home: no", "    books: {}" ]
      r <- loadSyncState cfg
      fmap (Map.map lsHome . syncLibraries) r
        `shouldBe` Right (Map.fromList [("A", HomeYes), ("B", HomeNo)])

  it "rejects unknown field keys" $
    withSystemTempDirectory "libri-sync" $ \dir -> do
      TIO.writeFile (dir </> "calibre-sync.yaml") $ T.intercalate "\n"
        [ "libraries:", "  A:", "    path: /a", "    home: no", "    books:"
        , "      \"A:1\":", "        status: mapped", "        book: x"
        , "        fields: {bogus: abc}" ]
      r <- loadSyncState (defaultConfig { _dataDir = dir })
      r `shouldSatisfy` either (const True) (const False)

  it "setHomeLibrary moves the home marker" $ do
    let mk h = LibrarySync "/p" h Map.empty
        st = SyncState (Map.fromList [("A", mk HomeYes), ("B", mk HomeUnanswered)])
        st' = setHomeLibrary "B" st
    Map.map lsHome (syncLibraries st') `shouldBe`
      Map.fromList [("A", HomeFormer), ("B", HomeYes)]

  it "setHomeLibrary demotes the previous home to former, leaving no and former alone" $ do
    let mk h = LibrarySync "/p" h Map.empty
        st = SyncState (Map.fromList
          [("A", mk HomeFormer), ("B", mk HomeYes), ("C", mk HomeNo), ("D", mk HomeUnanswered)])
    Map.map lsHome (syncLibraries (setHomeLibrary "D" st)) `shouldBe`
      Map.fromList [("A", HomeFormer), ("B", HomeFormer), ("C", HomeNo), ("D", HomeYes)]

  it "writes and reads a former home library as \"former\"" $
    withSystemTempDirectory "libri-sync" $ \dir -> do
      let cfg = defaultConfig { _dataDir = dir }
          st = SyncState (Map.singleton "A" (LibrarySync "/a" HomeFormer Map.empty))
      saveSyncState cfg st `shouldReturn` Right ()
      raw <- TIO.readFile (dir </> "calibre-sync.yaml")
      raw `shouldSatisfy` ("home: former" `T.isInfixOf`)
      loadSyncState cfg `shouldReturn` Right st
