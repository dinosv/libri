{-# LANGUAGE LambdaCase #-}

module CalibreImportDriverSpec (spec) where

import Control.Monad (forM)
import Data.Aeson (Value(..))
import Data.IORef (atomicModifyIORef', modifyIORef', newIORef, readIORef)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import System.Directory (doesFileExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import Libri.CLI.CalibreImport
import Libri.Storage.CalibreImport (CalibreLibrary(..))
import Libri.Storage.CalibreSync
import Libri.Storage.Yaml (loadBooksWithErrors, saveBook)
import Libri.Types (Book(..), BookId, Config(..), LibriError, defaultConfig)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

libUuid :: Text
libUuid = "lib-uuid"

cfgFor :: FilePath -> Config
cfgFor dir = defaultConfig { _dataDir = dir }

blank :: BookId -> Text -> Book
blank bid t = Book
  { _bookId = bid
  , _isbn = Nothing
  , _title = t
  , _authors = ["Autor " <> t]
  , _series = Nothing
  , _seriesIndex = Nothing
  , _publisher = Nothing
  , _published = Nothing
  , _tags = []
  , _rating = Nothing
  , _comments = Nothing
  , _location = Nothing
  , _custom = Map.empty
  , _added = UTCTime (fromGregorian 2025 1 1) 0
  , _modified = UTCTime (fromGregorian 2025 1 1) 0
  }

-- | A curated libri book carrying a bare Calibre id, as the real data does.
libriBook :: Int -> Book
libriBook n = (blank (libriId n) ("Libro " <> tshow n))
  { _tags = ["Filosofía"]
  , _location = Just "Shelf A"
  , _comments = Just "Comentario original"
  , _custom = Map.singleton "identifier:calibre" (String (tshow n))
  }

libriId :: Int -> BookId
libriId n = "aaaa000" <> tshow n <> "-0000-0000-0000-000000000000"

-- | The same book as Calibre has it: uncurated tags, namespaced ref.
calBook :: Int -> Book
calBook n = (blank ("cccc000" <> tshow n <> "-0000-0000-0000-000000000000") ("Libro " <> tshow n))
  { _tags = ["philosophy"]
  , _comments = Just "Comentario original"
  , _custom = Map.singleton "identifier:calibre" (String (refOf n))
  }

refOf :: Int -> Text
refOf n = libUuid <> ":" <> tshow n

library :: [Book] -> CalibreLibrary
library = CalibreLibrary libUuid "/calibre/Library"

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

-- | Run the import with scripted answers; returns the result and the
-- prompts that were asked (including those that hit EOF).
runWith :: FilePath -> [Text] -> CalibreLibrary
        -> IO (Either LibriError ImportSummary, [Text])
runWith dir answers lib = (\(r, ps, _) -> (r, ps)) <$> runFull dir answers lib

-- | As 'runWith', also returning the printed lines.
runFull :: FilePath -> [Text] -> CalibreLibrary
        -> IO (Either LibriError ImportSummary, [Text], [Text])
runFull dir answers lib = do
  ansRef <- newIORef answers
  promptRef <- newIORef []
  outRef <- newIORef ([] :: [Text])
  let ask p = do
        modifyIORef' promptRef (p :)
        atomicModifyIORef' ansRef $ \case
          []       -> ([], Nothing)
          (a : as) -> (as, Just a)
      say l = modifyIORef' outRef (l :)
  r <- runCalibreImport (cfgFor dir) ask say lib
  ps <- reverse <$> readIORef promptRef
  out <- reverse <$> readIORef outRef
  pure (r, ps, out)

-- | Run and require success.
runOk :: FilePath -> [Text] -> CalibreLibrary -> IO (ImportSummary, [Text])
runOk dir answers lib = runWith dir answers lib >>= \case
  (Right s, ps) -> pure (s, ps)
  (Left e, _)   -> expectationFailure ("import failed: " <> show e) >> fail "unreachable"

seed :: FilePath -> [Book] -> IO ()
seed dir = mapM_ $ \bk -> saveBook (cfgFor dir) bk >>= either (fail . show) pure

-- | Every book file's name and contents.
snapshot :: FilePath -> IO (Map FilePath Text)
snapshot dir = do
  let booksDir = dir </> "books"
  files <- listDirectory booksDir
  Map.fromList <$> forM files (\f -> (f,) <$> TIO.readFile (booksDir </> f))

loaded :: FilePath -> IO [Book]
loaded dir = snd <$> loadBooksWithErrors (cfgFor dir)

bookById :: FilePath -> BookId -> IO Book
bookById dir bid = loaded dir >>= \bs -> case filter ((== bid) . _bookId) bs of
  [bk] -> pure bk
  _    -> fail ("no unique book " <> T.unpack bid)

libSync :: FilePath -> IO LibrarySync
libSync dir = loadSyncState (cfgFor dir) >>= \case
  Right st | Just ls <- Map.lookup libUuid (syncLibraries st) -> pure ls
  other -> fail ("no library sync: " <> show other)

-- | Collection of libri books 1 and 2, after a baseline run that answered
-- "this is the home library" and ignored Calibre book 3.
baselined :: FilePath -> IO ()
baselined dir = do
  seed dir [libriBook 1, libriBook 2]
  _ <- runOk dir ["y", "i"] (library [calBook 1, calBook 2, calBook 3])
  pure ()

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Calibre import driver" $ do
  it "adds everything without questions into an empty collection" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      (s, ps) <- runOk dir [] (library [calBook 1, calBook 2, calBook 3])
      ps `shouldBe` []
      sumAdded s `shouldBe` 3
      sumUnanswered s `shouldBe` 0
      bs <- loaded dir
      length bs `shouldBe` 3
      ls <- libSync dir
      lsHome ls `shouldBe` HomeYes
      lsPath ls `shouldBe` "/calibre/Library"
      Map.lookup (refOf 2) (lsBooks ls)
        `shouldBe` Just (SyncMapped (_bookId (calBook 2)) (fieldPrints (calBook 2)))

  it "baseline: maps bare ids, changes nothing, records an ignored book" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      seed dir [libriBook 1, libriBook 2]
      snap0 <- snapshot dir
      (s, ps) <- runOk dir ["y", "i"] (library [calBook 1, calBook 2, calBook 3])
      length ps `shouldBe` 2
      (sumAdded s, sumUnchanged s, sumIgnored s, sumUnanswered s) `shouldBe` (0, 2, 1, 0)
      snapshot dir >>= (`shouldBe` snap0)
      ls <- libSync dir
      lsHome ls `shouldBe` HomeYes
      Map.lookup (refOf 1) (lsBooks ls)
        `shouldBe` Just (SyncMapped (libriId 1) (fieldPrints (calBook 1)))
      Map.lookup (refOf 3) (lsBooks ls) `shouldBe` Just SyncIgnored
      -- Second run: the ignored book stays out, and nothing is asked.
      (s2, ps2) <- runOk dir [] (library [calBook 1, calBook 2, calBook 3])
      ps2 `shouldBe` []
      (sumAdded s2, sumIgnored s2, sumUnanswered s2) `shouldBe` (0, 1, 0)
      snapshot dir >>= (`shouldBe` snap0)

  it "later run: [c] takes Calibre's changed comments and leaves tags alone" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      baselined dir
      let changed = (calBook 1) { _comments = Just "Nuevo comentario" }
          lib = library [changed, calBook 2, calBook 3]
      (s, ps) <- runOk dir ["c"] lib
      length ps `shouldBe` 1
      (sumResolved s, sumUnchanged s, sumUnanswered s) `shouldBe` (1, 1, 0)
      bk <- bookById dir (libriId 1)
      _comments bk `shouldBe` Just "Nuevo comentario"
      _tags bk `shouldBe` ["Filosofía"]
      _location bk `shouldBe` Just "Shelf A"
      (_, ps3) <- runOk dir [] lib
      ps3 `shouldBe` []

  it "later run: [l] keeps libri but records Calibre's prints" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      baselined dir
      snap0 <- snapshot dir
      let changed = (calBook 1) { _comments = Just "Nuevo comentario" }
          lib = library [changed, calBook 2, calBook 3]
      (s, ps) <- runOk dir ["l"] lib
      length ps `shouldBe` 1
      sumResolved s `shouldBe` 1
      snapshot dir >>= (`shouldBe` snap0)
      ls <- libSync dir
      Map.lookup (refOf 1) (lsBooks ls)
        `shouldBe` Just (SyncMapped (libriId 1) (fieldPrints changed))
      (_, ps2) <- runOk dir [] lib
      ps2 `shouldBe` []

  it "field by field: EOF after the first field keeps libri for the rest" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      baselined dir
      let changed = (calBook 1) { _title = "Libro Uno", _comments = Just "Nuevo comentario" }
      (s, ps) <- runOk dir ["f", "c"] (library [changed, calBook 2, calBook 3])
      length ps `shouldBe` 3
      sumUnanswered s `shouldBe` 1
      sumResolved s `shouldBe` 0
      bk <- bookById dir (libriId 1)
      _title bk `shouldBe` "Libro Uno"
      _comments bk `shouldBe` Just "Comentario original"
      length <$> loaded dir >>= (`shouldBe` 2)
      -- The entry keeps the baseline prints, so the undecided comments
      -- come back next run; the title already taken is not asked again.
      ls <- libSync dir
      Map.lookup (refOf 1) (lsBooks ls)
        `shouldBe` Just (SyncMapped (libriId 1) (fieldPrints (calBook 1)))
      (r2, ps2, out2) <- runFull dir ["l"] (library [changed, calBook 2, calBook 3])
      fmap sumResolved r2 `shouldBe` Right 1
      length ps2 `shouldBe` 1
      filter ("  comments" `T.isPrefixOf`) out2 `shouldSatisfy` ((== 1) . length)
      filter ("  title" `T.isPrefixOf`) out2 `shouldBe` []

  it "a comments change after character 60 is shown differently for each side" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      let long = T.pack (take 200 (cycle "abcdefghij"))
          edited = T.take 150 long <> "Z" <> T.drop 151 long
      seed dir [(libriBook 1) { _comments = Just long }, libriBook 2]
      _ <- runOk dir ["y", "i"]
        (library [(calBook 1) { _comments = Just long }, calBook 2, calBook 3])
      (_, _, out) <- runFull dir ["l"]
        (library [(calBook 1) { _comments = Just edited }, calBook 2, calBook 3])
      case filter ("  comments" `T.isPrefixOf`) out of
        [line] -> do
          let (l, c) = T.breakOn "  |  Calibre: " line
              libriSide = T.drop (T.length "libri: ") (snd (T.breakOn "libri: " l))
              calibreSide = T.drop (T.length "  |  Calibre: ") c
          libriSide `shouldSatisfy` (not . T.null)
          libriSide `shouldNotBe` calibreSide
        other -> expectationFailure ("expected one comments line, got " <> show other)

  it "EOF at the conflict prompt changes nothing and asks again next run" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      baselined dir
      snap0 <- snapshot dir
      let changed = (calBook 1) { _comments = Just "Nuevo comentario" }
          lib = library [changed, calBook 2, calBook 3]
      (s, ps) <- runOk dir [] lib
      length ps `shouldBe` 1
      (sumUnanswered s, sumResolved s) `shouldBe` (1, 0)
      snapshot dir >>= (`shouldBe` snap0)
      ls <- libSync dir
      Map.lookup (refOf 1) (lsBooks ls)
        `shouldBe` Just (SyncMapped (libriId 1) (fieldPrints (calBook 1)))
      (s2, ps2) <- runOk dir ["c"] lib
      length ps2 `shouldBe` 1
      sumResolved s2 `shouldBe` 1
      _comments <$> bookById dir (libriId 1) >>= (`shouldBe` Just "Nuevo comentario")

  it "non-interactive baseline: nothing added, home unanswered, books pending" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      seed dir [libriBook 1, libriBook 2]
      snap0 <- snapshot dir
      (s, _) <- runOk dir [] (library [calBook 1, calBook 2, calBook 3])
      sumAdded s `shouldBe` 0
      sumUnanswered s `shouldSatisfy` (> 0)
      snapshot dir >>= (`shouldBe` snap0)
      ls <- libSync dir
      lsHome ls `shouldBe` HomeUnanswered
      Map.lookup (refOf 3) (lsBooks ls) `shouldBe` Just SyncPending

  it "a pending book that now matches by bare id is mapped, not offered as new" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      seed dir [libriBook 1, libriBook 2]
      snap0 <- snapshot dir
      let lib = library [calBook 1, calBook 2, calBook 3]
      _ <- runOk dir [] lib
      (s, ps) <- runOk dir ["y", "i"] lib
      length ps `shouldBe` 2
      (sumAdded s, sumUnchanged s, sumIgnored s) `shouldBe` (0, 2, 1)
      snapshot dir >>= (`shouldBe` snap0)
      ls <- libSync dir
      Map.lookup (refOf 1) (lsBooks ls)
        `shouldBe` Just (SyncMapped (libriId 1) (fieldPrints (calBook 1)))

  it "ISBN guess: [s] maps the book and asks about every differing field" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      let mine = (blank (libriId 7) "Libro 7")
            { _isbn = Just "978-0-00-000000-1", _comments = Just "Mío" }
          theirs = (calBook 7) { _isbn = Just "9780000000001", _comments = Just "Suyo" }
      seed dir [mine]
      (s, ps) <- runOk dir ["n", "s", "c"] (library [theirs])
      length ps `shouldBe` 3
      (sumAdded s, sumResolved s) `shouldBe` (0, 1)
      bk <- bookById dir (libriId 7)
      _comments bk `shouldBe` Just "Suyo"
      length <$> loaded dir >>= (`shouldBe` 1)
      ls <- libSync dir
      lsHome ls `shouldBe` HomeNo
      Map.lookup (refOf 7) (lsBooks ls)
        `shouldBe` Just (SyncMapped (libriId 7) (fieldPrints theirs))

  it "ISBN guess: [s] then EOF keeps the link and asks the conflict again" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      let mine = (blank (libriId 7) "Libro 7")
            { _isbn = Just "9780000000001", _comments = Just "Mío" }
          theirs = (calBook 7) { _isbn = Just "9780000000001", _comments = Just "Suyo" }
          lib = library [theirs]
      seed dir [mine]
      snap0 <- snapshot dir
      (s, ps) <- runOk dir ["n", "s"] lib
      length ps `shouldBe` 3
      sumUnanswered s `shouldBe` 1
      snapshot dir >>= (`shouldBe` snap0)
      ls <- libSync dir
      Map.lookup (refOf 7) (lsBooks ls) `shouldBe` Just (SyncMapped (libriId 7) Map.empty)
      (s2, ps2) <- runOk dir ["c"] lib
      length ps2 `shouldBe` 1
      filter ("same book" `T.isInfixOf`) ps2 `shouldBe` []
      (sumResolved s2, sumAdded s2) `shouldBe` (1, 0)
      _comments <$> bookById dir (libriId 7) >>= (`shouldBe` Just "Suyo")

  it "aborts without writing anything when a book file is corrupt" $
    withSystemTempDirectory "libri-drv" $ \dir -> do
      seed dir [libriBook 1]
      TIO.writeFile (dir </> "books" </> "broken.yaml") "title: [oops"
      snap0 <- snapshot dir
      (r, ps) <- runWith dir ["y", "a"] (library [calBook 1, calBook 2])
      ps `shouldBe` []
      case r of
        Left e  -> show e `shouldContain` "broken.yaml"
        Right s -> expectationFailure ("expected Left, got " <> show s)
      snapshot dir >>= (`shouldBe` snap0)
      doesFileExist (dir </> "calibre-sync.yaml") >>= (`shouldBe` False)
