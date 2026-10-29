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
    -- * Sync state
  , HomeStatus(..)
  , SyncEntry(..)
  , LibrarySync(..)
  , SyncState(..)
  , emptySyncState
  , setHomeLibrary
  , syncFilePath
  , loadSyncState
  , saveSyncState
  ) where

import Control.Exception (try)
import Data.Aeson (FromJSON(..), ToJSON(..), Value(..), object, withObject, withText, (.:), (.=))
import Data.Aeson.Types (Parser)
import Data.Yaml (decodeFileEither, prettyPrintParseException)
import System.Directory (doesFileExist)
import System.FilePath ((</>))
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

import Libri.Storage.Yaml (encodeFileAtomic, getDataDir)
import Libri.Types (BookId, Book(..), Config, LibriError(..))

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

-- ---------------------------------------------------------------------------
-- Sync state
-- ---------------------------------------------------------------------------

-- | Whether a Calibre library is the one this libri collection lives in.
data HomeStatus = HomeYes | HomeNo | HomeUnanswered
  deriving (Show, Eq)

-- | What is known about one Calibre book.  'SyncPending' means it was seen
-- on a baseline run and left undecided; it is asked about again next run.
data SyncEntry
  = SyncMapped BookId FieldPrints
  | SyncIgnored
  | SyncPending
  deriving (Show, Eq)

-- | Sync state of one Calibre library.  Book keys are namespaced refs
-- (@\<library uuid\>:\<calibre id\>@).
data LibrarySync = LibrarySync
  { lsPath  :: FilePath
  , lsHome  :: HomeStatus
  , lsBooks :: Map Text SyncEntry
  } deriving (Show, Eq)

-- | Sync state of all known libraries, keyed by library UUID.
newtype SyncState = SyncState { syncLibraries :: Map Text LibrarySync }
  deriving (Show, Eq)

emptySyncState :: SyncState
emptySyncState = SyncState Map.empty

-- | Make a library the home library; any other home library becomes 'HomeNo'.
setHomeLibrary :: Text -> SyncState -> SyncState
setHomeLibrary uuid (SyncState libs) = SyncState (Map.mapWithKey mark libs)
  where
    mark k ls
      | k == uuid           = ls { lsHome = HomeYes }
      | lsHome ls == HomeYes = ls { lsHome = HomeNo }
      | otherwise           = ls

instance ToJSON HomeStatus where
  toJSON = String . \case
    HomeYes        -> "yes"
    HomeNo         -> "no"
    HomeUnanswered -> "unanswered"

-- | Also accepts YAML booleans, since an unquoted yes/no in a hand-edited
-- file is read as one.
instance FromJSON HomeStatus where
  parseJSON (Bool True)  = pure HomeYes
  parseJSON (Bool False) = pure HomeNo
  parseJSON v = withText "HomeStatus" (\case
    "yes"        -> pure HomeYes
    "no"         -> pure HomeNo
    "unanswered" -> pure HomeUnanswered
    t            -> fail ("unknown home status: " <> T.unpack t)) v

instance ToJSON SyncEntry where
  toJSON = \case
    SyncIgnored -> object ["status" .= ("ignored" :: Text)]
    SyncPending -> object ["status" .= ("pending" :: Text)]
    SyncMapped bid prints -> object
      [ "status" .= ("mapped" :: Text)
      , "book"   .= bid
      , "fields" .= Map.fromList [ (fieldKey f, h) | (f, h) <- Map.toList prints ]
      ]

instance FromJSON SyncEntry where
  parseJSON = withObject "SyncEntry" $ \o -> do
    status <- o .: "status" :: Parser Text
    case status of
      "ignored" -> pure SyncIgnored
      "pending" -> pure SyncPending
      "mapped"  -> do
        bid <- o .: "book"
        raw <- o .: "fields" :: Parser (Map Text Text)
        SyncMapped bid . Map.fromList <$> traverse field (Map.toList raw)
      _ -> fail ("unknown sync status: " <> T.unpack status)
    where
      field (k, h) = case lookup k [ (fieldKey f, f) | f <- [minBound .. maxBound] ] of
        Just f  -> pure (f, h)
        Nothing -> fail ("unknown field key: " <> T.unpack k)

instance ToJSON LibrarySync where
  toJSON (LibrarySync path home books) = object
    [ "path" .= path, "home" .= home, "books" .= books ]

instance FromJSON LibrarySync where
  parseJSON = withObject "LibrarySync" $ \o ->
    LibrarySync <$> o .: "path" <*> o .: "home" <*> o .: "books"

instance ToJSON SyncState where
  toJSON (SyncState libs) = object ["libraries" .= libs]

instance FromJSON SyncState where
  parseJSON = withObject "SyncState" $ \o -> SyncState <$> o .: "libraries"

-- | Location of the sync-state file inside the data directory.
syncFilePath :: Config -> IO FilePath
syncFilePath cfg = (</> "calibre-sync.yaml") <$> getDataDir cfg

-- | Load the sync state.  A missing file is the empty state; an unreadable
-- one is an error and is never overwritten here.
loadSyncState :: Config -> IO (Either LibriError SyncState)
loadSyncState cfg = do
  path <- syncFilePath cfg
  exists <- doesFileExist path
  if not exists
    then pure (Right emptySyncState)
    else do
      r <- try (decodeFileEither path)
      pure $ case r of
        Left (e :: IOError)  -> Left (ParseError path (show e))
        Right (Left e)       -> Left (ParseError path (prettyPrintParseException e))
        Right (Right st)     -> Right st

-- | Atomically write the sync state.
saveSyncState :: Config -> SyncState -> IO (Either LibriError ())
saveSyncState cfg st = do
  path <- syncFilePath cfg
  r <- try (encodeFileAtomic path st)
  pure $ case r of
    Left (e :: IOError) -> Left (ParseError path (show e))
    Right ()            -> Right ()
