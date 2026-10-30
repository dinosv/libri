-- | The interactive, state-aware Calibre import.
--
-- Matches every incoming Calibre book against the live collection and the
-- sync state, adds new books, and asks the user about anything that would
-- change a libri book.  Every question has a non-destructive answer on EOF,
-- so a non-interactive run never overwrites, ignores or adds by guesswork.
module Libri.CLI.CalibreImport
  ( Ask
  , ImportSummary(..)
  , runCalibreImport
  ) where

import Control.Monad (forM_, unless)
import Control.Monad.State.Strict (StateT, execStateT, gets, liftIO, modify')
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import Libri.Storage.CalibreImport (CalibreLibrary(..))
import Libri.Storage.CalibreReconcile
  ( FieldChoice(..), Match(..), applyChoices, calibreRefOf, changedFields
  , differingFields, fieldDisplay, matchBook )
import Libri.Storage.CalibreSync
  ( CalibreField(..), HomeStatus(..), LibrarySync(..), SyncEntry(..)
  , SyncState(..), fieldKey, fieldPrints, loadSyncState, saveSyncState
  , setHomeLibrary )
import Libri.Storage.Yaml (loadBooksWithErrors, saveBook)
import Libri.Types (Book(..), Config, LibriError(..))

-- | Show a prompt and return the stripped answer; 'Nothing' on EOF.
type Ask = Text -> IO (Maybe Text)

-- | What one import run did.
data ImportSummary = ImportSummary
  { sumAdded, sumUnchanged, sumResolved, sumIgnored, sumDeletedInLibri
  , sumUnanswered, sumFailures :: Int
  } deriving (Show, Eq)

-- | Import a Calibre library into the collection, asking the user through
-- the 'Ask' and reporting through the line printer.  Aborts without writing
-- anything if a book file or the sync state cannot be read.
runCalibreImport :: Config -> Ask -> (Text -> IO ()) -> CalibreLibrary
                 -> IO (Either LibriError ImportSummary)
runCalibreImport cfg ask say' lib = do
  (errs, coll) <- loadBooksWithErrors cfg
  if not (null errs)
    then pure (Left (CalibreImportError
      ("unreadable book files, nothing imported: "
        <> T.unpack (T.intercalate ", " (map (T.pack . fst) errs)))))
    else loadSyncState cfg >>= \case
      Left e -> pure (Left e)
      Right st0 -> do
        let uuid = clUuid lib
            known = Map.lookup uuid (syncLibraries st0)
            fresh = LibrarySync (clPath lib) HomeUnanswered Map.empty
            st1 = SyncState (Map.insert uuid (maybe fresh id known) (syncLibraries st0))
            env = Env cfg ask say' uuid (isNothing known)
            homeUnknown = maybe True ((== HomeUnanswered) . lsHome) known
            run0 = Run coll st1 emptySummary False []
        final <- execStateT (driver env lib (null coll) homeUnknown) run0
        let setPath ls = ls { lsPath = clPath lib }
            st' = SyncState (Map.adjust setPath uuid (syncLibraries (rSync final)))
        fmap (const (rSum final)) <$> saveSyncState cfg st'

-- ---------------------------------------------------------------------------
-- Run state
-- ---------------------------------------------------------------------------

-- | Fixed context of one run.
data Env = Env
  { envCfg      :: Config
  , envAsk      :: Ask
  , envSay      :: Text -> IO ()
  , envUuid     :: Text
  , envBaseline :: Bool   -- ^ no sync entry for this library before the run
  }

-- | What changes during a run.
data Run = Run
  { rColl      :: [Book]        -- ^ live collection, updated after each save
  , rSync      :: SyncState
  , rSum       :: ImportSummary
  , rKeepAll   :: Bool          -- ^ the user answered [L]
  , rUndecided :: [Book]        -- ^ newest first
  }

type M = StateT Run IO

emptySummary :: ImportSummary
emptySummary = ImportSummary 0 0 0 0 0 0 0

data Counter = Added | Unchanged | Resolved | Ignored | Deleted | Unanswered | Failed

count :: Counter -> M ()
count c = modify' $ \r -> r { rSum = bump (rSum r) }
  where
    bump s = case c of
      Added      -> s { sumAdded = sumAdded s + 1 }
      Unchanged  -> s { sumUnchanged = sumUnchanged s + 1 }
      Resolved   -> s { sumResolved = sumResolved s + 1 }
      Ignored    -> s { sumIgnored = sumIgnored s + 1 }
      Deleted    -> s { sumDeletedInLibri = sumDeletedInLibri s + 1 }
      Unanswered -> s { sumUnanswered = sumUnanswered s + 1 }
      Failed     -> s { sumFailures = sumFailures s + 1 }

say :: Env -> Text -> M ()
say env = liftIO . envSay env

-- | This library's sync entry (always present during a run).
thisLibrary :: Env -> M (Maybe LibrarySync)
thisLibrary env = gets (Map.lookup (envUuid env) . syncLibraries . rSync)

modifyLibrary :: Env -> (LibrarySync -> LibrarySync) -> M ()
modifyLibrary env f = modify' $ \r ->
  r { rSync = SyncState (Map.adjust f (envUuid env) (syncLibraries (rSync r))) }

makeHome :: Env -> M ()
makeHome env = modify' $ \r -> r { rSync = setHomeLibrary (envUuid env) (rSync r) }

-- | Record what is known about an incoming Calibre book.
record :: Env -> Book -> SyncEntry -> M ()
record env inc entry = forM_ (calibreRefOf inc) $ \ref ->
  modifyLibrary env (\ls -> ls { lsBooks = Map.insert ref entry (lsBooks ls) })

-- | Map an incoming book to a libri book, storing Calibre's prints.
recordMapping :: Env -> Book -> Book -> M ()
recordMapping env inc bk = record env inc (SyncMapped (_bookId bk) (fieldPrints inc))

-- ---------------------------------------------------------------------------
-- Flow
-- ---------------------------------------------------------------------------

-- | Arguments after the library: the collection is empty; the home
-- question is still open.
driver :: Env -> CalibreLibrary -> Bool -> Bool -> M ()
driver env lib emptyCollection homeUnknown
  | emptyCollection = makeHome env >> mapM_ (addBook env) (clBooks lib)
  | otherwise = do
      bareOk <- if envBaseline env || homeUnknown
        then askHome env lib
        else maybe False ((== HomeYes) . lsHome) <$> thisLibrary env
      mapM_ (importOne env bareOk) (clBooks lib)
      decideUndecided env

-- | Ask whether this is the home library; True only on yes.
askHome :: Env -> CalibreLibrary -> M Bool
askHome env lib = do
  a <- choose env ("Is " <> T.pack (clPath lib)
                   <> " the Calibre library your collection came from? [y/n] ")
         [("y", True), ("n", False)]
  case a of
    Just True  -> makeHome env >> pure True
    Just False -> modifyLibrary env (\ls -> ls { lsHome = HomeNo }) >> pure False
    Nothing    -> count Unanswered >> pure False

-- | Match one incoming book.  A pending book is matched again without its
-- pending entry, so a book left undecided because the home question went
-- unanswered is mapped by its bare id once that is answered, instead of
-- being offered as new.
matchIncoming :: Env -> Bool -> Book -> M Match
matchIncoming env bareOk inc = do
  ls <- thisLibrary env
  coll <- gets rColl
  pure $ case matchBook bareOk ls coll inc of
    MatchPending ->
      let forget l = l { lsBooks = maybe id Map.delete (calibreRefOf inc) (lsBooks l) }
      in case matchBook bareOk (forget <$> ls) coll inc of
           NoMatch -> MatchPending
           m       -> m
    m -> m

importOne :: Env -> Bool -> Book -> M ()
importOne env bareOk inc = matchIncoming env bareOk inc >>= \case
  NoMatch
    | envBaseline env -> undecided
    | otherwise -> addBook env inc
  MatchPending -> undecided
  MatchByRef bk -> unchanged bk
  MatchBareRef bk -> unchanged bk
  MatchMapped bk stored ->
    case differingFields (changedFields stored (fieldPrints inc)) bk inc of
      [] -> unchanged bk
      fs -> conflict env inc bk fs (pure ())
  MatchIsbnGuess bk -> do
    say env ("Same ISBN as a libri book without a Calibre id: " <> describe bk)
    a <- choose env ("Is " <> describe inc <> " the same book? [s]ame book / [n]ew book ")
           [("s", True), ("n", False)]
    case a of
      Nothing -> count Unanswered
      Just False -> addBook env inc
      Just True -> case differingFields [minBound .. maxBound] bk inc of
        [] -> unchanged bk
        -- On EOF, keep the link but no prints, so every field counts as
        -- changed and the conflict (not "same book?") comes back.
        fs -> conflict env inc bk fs
                (record env inc (SyncMapped (_bookId bk) Map.empty))
  MatchIgnored -> count Ignored
  MatchDeletedInLibri -> do
    say env ("Skipped, deleted in libri: " <> describe inc)
    count Deleted
  where
    undecided = modify' $ \r -> r { rUndecided = inc : rUndecided r }
    unchanged bk = recordMapping env inc bk >> count Unchanged

-- | Save a new book and map it to its Calibre record.
addBook :: Env -> Book -> M ()
addBook env inc = liftIO (saveBook (envCfg env) inc) >>= \case
  Left e -> saveFailed env inc e
  Right () -> do
    modify' $ \r -> r { rColl = inc : rColl r }
    recordMapping env inc inc
    count Added
    say env ("Added: " <> describe inc)

saveFailed :: Env -> Book -> LibriError -> M ()
saveFailed env bk e = do
  count Failed
  say env ("Could not save " <> describe bk <> ": " <> T.pack (show e))

-- ---------------------------------------------------------------------------
-- Conflicts
-- ---------------------------------------------------------------------------

data Resolution = KeepAll | TakeAll | ByField | KeepRest

-- | Ask how to settle the fields where Calibre's change differs from libri.
-- Fields already chosen are saved.  Once every field is decided, Calibre's
-- prints are stored.  On EOF the last argument runs instead (the existing
-- entry is otherwise left as it is), so the undecided fields are asked
-- about again next run.  If the changed book cannot be saved, the entry
-- is left alone too.
conflict :: Env -> Book -> Book -> [CalibreField] -> M () -> M ()
conflict env inc bk fs onEof = do
  keepRest <- gets rKeepAll
  (choices, answered) <- if keepRest
    then say env ("Kept libri: " <> describe inc) >> pure ([], True)
    else do
      say env ("Changed in Calibre: " <> describe inc)
      forM_ fs $ \f -> say env (sideBySide f)
      choose env "[l] keep libri / [c] take Calibre / [f] field by field / [L] keep libri for all remaining "
          [("l", KeepAll), ("c", TakeAll), ("f", ByField), ("L", KeepRest)] >>= \case
        Nothing       -> pure ([], False)
        Just KeepAll  -> pure ([], True)
        Just TakeAll  -> pure (map (, TakeCalibre) fs, True)
        Just KeepRest -> modify' (\r -> r { rKeepAll = True }) >> pure ([], True)
        Just ByField  -> fieldByField env fs
  count (if answered then Resolved else Unanswered)
  let updated = applyChoices choices inc bk
      settle = if answered then recordMapping env inc bk else onEof
  if updated == bk
    then settle
    -- saveBook stamps _modified with the current time.
    else liftIO (saveBook (envCfg env) updated) >>= \case
      Left e -> saveFailed env bk e
      Right () -> do
        let swap b = if _bookId b == _bookId bk then updated else b
        modify' $ \r -> r { rColl = map swap (rColl r) }
        settle
  where
    sideBySide f = "  " <> T.justifyLeft 12 ' ' (fieldKey f)
      <> "libri: " <> flat (fieldDisplay f bk) <> "  |  Calibre: " <> flat (fieldDisplay f inc)
    flat = T.unwords . T.words

-- | Ask per field.  On EOF the remaining fields keep libri's value; the
-- flag says whether every field was answered.
fieldByField :: Env -> [CalibreField] -> M ([(CalibreField, FieldChoice)], Bool)
fieldByField env = go []
  where
    go acc [] = pure (reverse acc, True)
    go acc (f : rest) = choose env (prompt f) (opts f) >>= \case
      Nothing -> pure (reverse acc, False)
      Just c  -> go ((f, c) : acc) rest
    prompt f = fieldKey f <> ": [l] libri / [c] Calibre"
      <> (if f == FTags then " / [u] union " else " ")
    opts f = [("l", KeepLibri), ("c", TakeCalibre)]
      <> [ ("u", UnionTags) | f == FTags ]

-- ---------------------------------------------------------------------------
-- Undecided books
-- ---------------------------------------------------------------------------

data Decision = AddAll | IgnoreAll | OneByOne

-- | Ask about the books that are new on a baseline run or still pending.
-- On EOF every book not yet decided stays pending.
decideUndecided :: Env -> M ()
decideUndecided env = do
  us <- gets (reverse . rUndecided)
  unless (null us) $ do
    say env (T.pack (show (length us))
             <> (if length us == 1 then " Calibre book is" else " Calibre books are")
             <> " not in your collection:")
    forM_ us $ \b -> say env ("  " <> describe b)
    choose env "[a] add all / [i] ignore all / [o] one by one "
        [("a", AddAll), ("i", IgnoreAll), ("o", OneByOne)] >>= \case
      Nothing        -> mapM_ pending us
      Just AddAll    -> mapM_ (addBook env) us
      Just IgnoreAll -> mapM_ ignore us
      Just OneByOne  -> oneByOne us
  where
    oneByOne [] = pure ()
    oneByOne (b : rest) =
      choose env ("Add " <> describe b <> "? [a]dd / [i]gnore ")
          [("a", True), ("i", False)] >>= \case
        Nothing    -> mapM_ pending (b : rest)
        Just True  -> addBook env b >> oneByOne rest
        Just False -> ignore b >> oneByOne rest
    pending b = record env b SyncPending >> count Unanswered
    ignore b = record env b SyncIgnored >> count Ignored

-- ---------------------------------------------------------------------------
-- Prompts
-- ---------------------------------------------------------------------------

-- | Ask until the answer is one of the options; 'Nothing' on EOF.
choose :: Env -> Text -> [(Text, a)] -> M (Maybe a)
choose env prompt opts = loop
  where
    loop = liftIO (envAsk env prompt) >>= \case
      Nothing -> pure Nothing
      Just a
        | Just v <- lookup a opts -> pure (Just v)
        | otherwise -> do
            say env ("Please answer " <> T.intercalate ", " (map fst opts) <> ".")
            loop

-- | Title, first author and Calibre id, for listings and prompts.
describe :: Book -> Text
describe bk = "\"" <> _title bk <> "\""
  <> maybe "" (" by " <>) (listToMaybe (_authors bk))
  <> maybe "" (\r -> " (Calibre id " <> snd (T.breakOnEnd ":" r) <> ")") (calibreRefOf bk)
