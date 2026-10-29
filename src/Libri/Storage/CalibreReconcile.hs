-- | Reconciling an incoming Calibre book with the libri collection.
module Libri.Storage.CalibreReconcile
  ( -- * Matching
    Match(..)
  , calibreRefOf
  , matchBook
  ) where

import Data.Aeson (Value(..))
import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import Data.Text (Text)
import qualified Data.Text as T

import Libri.CLI.BatchImport (normalizeISBN)
import Libri.Storage.CalibreSync (FieldPrints, LibrarySync(..), SyncEntry(..))
import Libri.Types (Book(..))

-- ---------------------------------------------------------------------------
-- Matching
-- ---------------------------------------------------------------------------

-- | The libri book (if any) an incoming Calibre book corresponds to.
data Match
  = MatchMapped Book FieldPrints  -- ^ sync entry; carries the stored prints
  | MatchIgnored                  -- ^ the user chose to skip this book
  | MatchPending                  -- ^ awaiting a decision
  | MatchDeletedInLibri           -- ^ mapped, but the libri book is gone
  | MatchByRef Book               -- ^ same namespaced @identifier:calibre@
  | MatchBareRef Book             -- ^ same bare Calibre id (home library only)
  | MatchIsbnGuess Book           -- ^ equal ISBN, no Calibre identifier
  | NoMatch
  deriving (Show, Eq)

-- | The @identifier:calibre@ string of a book, if it has one.
calibreRefOf :: Book -> Maybe Text
calibreRefOf bk = case Map.lookup "identifier:calibre" (_custom bk) of
  Just (String t) -> Just t
  _               -> Nothing

-- | Find the libri book for an incoming Calibre book, by strict priority:
-- sync entry, namespaced ref, bare id (only if the first argument is True,
-- i.e. this is the home library), then ISBN among books carrying no
-- @identifier:calibre@ at all.
matchBook :: Bool -> Maybe LibrarySync -> [Book] -> Book -> Match
matchBook bareOk msync coll inc =
  case ref >>= \r -> msync >>= Map.lookup r . lsBooks of
    Just (SyncMapped bid ps) ->
      maybe MatchDeletedInLibri (`MatchMapped` ps)
            (find ((== bid) . _bookId) coll)
    Just SyncIgnored -> MatchIgnored
    Just SyncPending -> MatchPending
    Nothing
      | Just bk <- byRef -> MatchByRef bk
      | bareOk, Just bk <- byBare -> MatchBareRef bk
      | Just bk <- byIsbn -> MatchIsbnGuess bk
      | otherwise -> NoMatch
  where
    ref = calibreRefOf inc
    byRef = ref >>= \r -> find ((== Just r) . calibreRefOf) coll
    byBare = do
      r <- ref
      let bare = snd (T.breakOnEnd ":" r)
      find ((== Just bare) . calibreRefOf) coll
    key = T.toUpper . normalizeISBN
    byIsbn = do
      i <- _isbn inc
      let k = key i
      if T.null k then Nothing else
        find (\b -> isNothing (Map.lookup "identifier:calibre" (_custom b))
                    && fmap key (_isbn b) == Just k) coll
