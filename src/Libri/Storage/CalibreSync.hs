-- | Change detection for Calibre re-imports.
--
-- A fingerprint is a short hash of a canonical rendering of one field of a
-- Calibre record.  Comparing fingerprints between imports shows which fields
-- changed in Calibre since the last sync.
module Libri.Storage.CalibreSync
  ( -- * Fingerprints
    CalibreField(..)
  , fieldKey
  , fieldCanonical
  , FieldPrints
  , fieldPrints
  , fnv1a64Hex
    -- * Identifiers
  , calibreIdentifiers
  ) where

import Data.Aeson (Value(..))
import Data.Bits (xor)
import qualified Data.ByteString as BS
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word64)
import Numeric (showHex)

import Libri.Types (Book(..))

-- ---------------------------------------------------------------------------
-- Fingerprints
-- ---------------------------------------------------------------------------

-- | Fields of a Calibre record that are tracked for changes.
data CalibreField
  = FTitle | FAuthors | FSeries | FSeriesIndex | FPublisher | FPublished
  | FIsbn | FTags | FRating | FComments | FIdentifiers
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Stable textual key of a field, used in the sync-state file.
fieldKey :: CalibreField -> Text
fieldKey = \case
  FTitle       -> "title"
  FAuthors     -> "authors"
  FSeries      -> "series"
  FSeriesIndex -> "seriesIndex"
  FPublisher   -> "publisher"
  FPublished   -> "published"
  FIsbn        -> "isbn"
  FTags        -> "tags"
  FRating      -> "rating"
  FComments    -> "comments"
  FIdentifiers -> "identifiers"

-- | Fingerprint of every tracked field of a book.
type FieldPrints = Map CalibreField Text

-- | Fingerprints for all fields.
fieldPrints :: Book -> FieldPrints
fieldPrints book = Map.fromList
  [ (f, fnv1a64Hex (fieldCanonical f book)) | f <- [minBound .. maxBound] ]

-- | Canonical text of a field; equal text means "unchanged".  Tags and
-- identifiers are order-insensitive, authors are not, and a missing value
-- differs from an empty one.
fieldCanonical :: CalibreField -> Book -> Text
fieldCanonical field book = case field of
  FTitle       -> _title book
  FAuthors     -> joinUS (_authors book)
  FSeries      -> maybeText id (_series book)
  FSeriesIndex -> maybeText (T.pack . show) (_seriesIndex book)
  FPublisher   -> maybeText id (_publisher book)
  FPublished   -> maybeText (T.pack . show) (_published book)
  FIsbn        -> maybeText id (_isbn book)
  FTags        -> joinUS (sort (_tags book))
  FRating      -> maybeText (T.pack . show) (_rating book)
  FComments    -> maybeText id (_comments book)
  FIdentifiers -> joinUS
    [ k <> "=" <> renderValue v | (k, v) <- Map.toAscList (calibreIdentifiers book) ]
  where
    joinUS = T.intercalate "\US"
    maybeText render = maybe "-" (("+" <>) . render)
    renderValue = \case
      String s -> s
      v        -> T.pack (show v)

-- | FNV-1a 64-bit hash of the UTF-8 encoding, as 16 lowercase hex digits.
fnv1a64Hex :: Text -> Text
fnv1a64Hex t = T.justifyRight 16 '0' (T.pack (showHex h ""))
  where
    h :: Word64
    h = BS.foldl' step 0xcbf29ce484222325 (encodeUtf8 t)
    step acc byte = (acc `xor` fromIntegral byte) * 0x100000001b3

-- ---------------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------------

-- | Calibre identifiers kept in a book's custom fields (keys starting with
-- @identifier:@), excluding the @identifier:calibre@ provenance key.
calibreIdentifiers :: Book -> Map Text Value
calibreIdentifiers = Map.filterWithKey keep . _custom
  where
    keep k _ = "identifier:" `T.isPrefixOf` k && k /= "identifier:calibre"
