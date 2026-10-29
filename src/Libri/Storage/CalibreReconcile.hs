-- | Reconciling an incoming Calibre book with the libri collection.
module Libri.Storage.CalibreReconcile
  ( -- * Matching
    Match(..)
  , calibreRefOf
  , matchBook
    -- * Conflicts
  , FieldChoice(..)
  , changedFields
  , differingFields
  , applyChoices
  , fieldDisplay
  ) where

import Data.Aeson (Value(..))
import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import Data.Text (Text)
import qualified Data.Text as T

import Libri.CLI.BatchImport (normalizeISBN)
import Libri.Storage.CalibreSync
  ( CalibreField(..), FieldPrints, LibrarySync(..), SyncEntry(..)
  , calibreIdentifiers, fieldCanonical )
import Libri.Text.Normalize (normalizeText)
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

-- ---------------------------------------------------------------------------
-- Conflicts
-- ---------------------------------------------------------------------------

-- | What to do with one field of a changed book.
data FieldChoice = KeepLibri | TakeCalibre | UnionTags
  deriving (Show, Eq)

-- | Fields whose incoming print differs from the stored one, or is missing
-- from the stored prints.
changedFields :: FieldPrints -> FieldPrints -> [CalibreField]
changedFields stored incoming =
  [ f | (f, p) <- Map.toAscList incoming, Map.lookup f stored /= Just p ]

-- | Of the given fields, those whose canonical text differs between the
-- libri book (first) and the Calibre book (second).
differingFields :: [CalibreField] -> Book -> Book -> [CalibreField]
differingFields fs libri cal =
  [ f | f <- fs, fieldCanonical f libri /= fieldCanonical f cal ]

-- | Apply per-field choices.  Arguments: choices, Calibre book, libri book.
-- Only fields chosen as 'TakeCalibre' or 'UnionTags' are touched; everything
-- else (id, location, added, other custom keys) stays libri's.
applyChoices :: [(CalibreField, FieldChoice)] -> Book -> Book -> Book
applyChoices choices cal = \libri -> foldl' step libri choices
  where
    step bk (f, c) = case c of
      KeepLibri   -> bk
      TakeCalibre -> takeField f bk
      UnionTags
        | f == FTags -> bk { _tags = unionTags (_tags bk) (_tags cal) }
        | otherwise  -> bk
    takeField f bk = case f of
      FTitle       -> bk { _title = _title cal }
      FAuthors     -> bk { _authors = _authors cal }
      FSeries      -> bk { _series = _series cal }
      FSeriesIndex -> bk { _seriesIndex = _seriesIndex cal }
      FPublisher   -> bk { _publisher = _publisher cal }
      FPublished   -> bk { _published = _published cal }
      FIsbn        -> bk { _isbn = _isbn cal }
      FTags        -> bk { _tags = _tags cal }
      FRating      -> bk { _rating = _rating cal }
      FComments    -> bk { _comments = _comments cal }
      FIdentifiers -> bk { _custom = Map.union (calibreIdentifiers cal) (_custom bk) }
    unionTags mine theirs = foldl' add mine theirs
    add acc t
      | any ((== normalizeText t) . normalizeText) acc = acc
      | otherwise = acc ++ [t]

-- | Human-readable value of a field, for the side-by-side display.
-- Comments are truncated to 60 characters.
fieldDisplay :: CalibreField -> Book -> Text
fieldDisplay field bk = case field of
  FTitle       -> _title bk
  FAuthors     -> T.intercalate ", " (_authors bk)
  FSeries      -> orDash id (_series bk)
  FSeriesIndex -> orDash (T.pack . show) (_seriesIndex bk)
  FPublisher   -> orDash id (_publisher bk)
  FPublished   -> orDash (T.pack . show) (_published bk)
  FIsbn        -> orDash id (_isbn bk)
  FTags        -> T.intercalate ", " (_tags bk)
  FRating      -> orDash (T.pack . show) (_rating bk)
  FComments    -> orDash truncated (_comments bk)
  FIdentifiers -> T.intercalate ", "
    [ T.drop (T.length "identifier:") k <> "=" <> render v
    | (k, v) <- Map.toAscList (calibreIdentifiers bk) ]
  where
    orDash f = maybe "-" f
    truncated t
      | T.length t > 60 = T.take 60 t <> "\8230"
      | otherwise = t
    render (String s) = s
    render v = T.pack (show v)
