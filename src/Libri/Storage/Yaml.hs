module Libri.Storage.Yaml
  ( -- * Loading
    loadBooks
  , loadBooksWithErrors
  , loadBook
  , loadConfig
  , loadLocations
    -- * Saving
  , saveBook
  , saveConfig
  , saveLocations
  , deleteBook
    -- * Merging
  , mergeBooks
    -- * Directory Management
  , initDataDir
  , getDataDir
  , expandPath
  ) where

import Control.Exception (try)
import Control.Monad (forM, when, void)
import Data.Either (lefts, rights)
import Data.List (isSuffixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Data.Yaml (ToJSON, decodeFileEither, encodeFile)
import Lens.Micro ((&), (.~))
import Libri.Types
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getHomeDirectory
  , listDirectory
  , removeFile
  , renameFile
  )
import System.FilePath ((</>))

-- | Expand ~ to home directory
expandPath :: FilePath -> IO FilePath
expandPath path
  | "~/" `isPrefixOf` path = do
      home <- getHomeDirectory
      pure $ home </> drop 2 path
  | path == "~" = getHomeDirectory
  | otherwise = pure path
  where
    isPrefixOf prefix str = take (length prefix) str == prefix

-- | Get the data directory, creating it if necessary
getDataDir :: Config -> IO FilePath
getDataDir cfg = do
  expanded <- expandPath (_dataDir cfg)
  createDirectoryIfMissing True expanded
  pure expanded

-- | Initialize data directory structure
initDataDir :: Config -> IO ()
initDataDir cfg = do
  dir <- getDataDir cfg
  createDirectoryIfMissing True (dir </> "books")
  -- Create default locations file if it doesn't exist
  let locFile = dir </> "locations.yaml"
  exists <- doesFileExist locFile
  when (not exists) $ do
    void $ saveLocations cfg defaultLocations
  where
    defaultLocations =
      [ "Shelf A"
      , "Shelf B"
      , "Storage"
      , "Lent Out"
      ]

-- | Load all books from the data directory.
-- Unreadable files are skipped; use 'loadBooksWithErrors' to see which ones.
loadBooks :: Config -> IO (Either LibriError [Book])
loadBooks cfg = Right . snd <$> loadBooksWithErrors cfg

-- | Load all books, returning per-file errors alongside the books that
-- did load. One corrupt file must not make the whole library unreadable.
loadBooksWithErrors :: Config -> IO ([(FilePath, LibriError)], [Book])
loadBooksWithErrors cfg = do
  dir <- getDataDir cfg
  let booksDir = dir </> "books"
  exists <- doesDirectoryExist booksDir
  if not exists
    then pure ([], [])
    else do
      files <- listDirectory booksDir
      -- Filter out non-book YAML files
      let isBookFile f = ".yaml" `isSuffixOf` f && f /= "locations.yaml" && f /= "config.yaml"
          yamlFiles = filter isBookFile files
      results <- forM yamlFiles $ \file -> do
        let path = booksDir </> file
        result <- loadBook path
        pure $ either (Left . (path,)) Right result
      pure (lefts results, rights results)

-- | Load a single book from a YAML file
loadBook :: FilePath -> IO (Either LibriError Book)
loadBook path = do
  exists <- doesFileExist path
  if not exists
    then pure $ Left $ FileNotFound path
    else do
      result <- decodeFileEither path
      case result of
        Left err -> pure $ Left $ ParseError path (show err)
        Right book -> pure $ Right book

-- | Encode to a temporary file, then rename over the target so a crash
-- mid-write can never truncate or corrupt the existing file.
encodeFileAtomic :: ToJSON a => FilePath -> a -> IO ()
encodeFileAtomic path val = do
  let tmp = path <> ".tmp"
  encodeFile tmp val
  renameFile tmp path

-- | Save a book to a YAML file
saveBook :: Config -> Book -> IO (Either LibriError ())
saveBook cfg book = do
  dir <- getDataDir cfg
  let booksDir = dir </> "books"
  createDirectoryIfMissing True booksDir
  now <- getCurrentTime
  let book' = book & modified .~ now
      filename = bookFilename book'
      path = booksDir </> filename
  result <- try $ encodeFileAtomic path book'
  case result of
    Left (e :: IOError) -> pure $ Left $ ParseError path (show e)
    Right () -> pure $ Right ()

-- | Merge a Calibre book with an existing libri book
-- Calibre data wins for most fields, but preserves:
-- - _location (libri-only)
-- - _added (original timestamp)
-- - non-identifier custom fields
mergeBooks :: Book -> Book -> Book
mergeBooks calibre existing =
  let -- Preserve non-identifier custom fields from existing
      existingNonIds = Map.filterWithKey
        (\k _ -> not (T.isPrefixOf "identifier:" k))
        (_custom existing)
      -- Get identifier fields from calibre
      calibreIds = Map.filterWithKey
        (\k _ -> T.isPrefixOf "identifier:" k)
        (_custom calibre)
      -- Merge: existing non-ids + calibre ids
      mergedCustom = Map.union calibreIds existingNonIds
   in calibre
        { _bookId = _bookId existing
        , _location = _location existing
        , _added = _added existing
        , _custom = mergedCustom
        }

-- | Delete a book's YAML file
deleteBook :: Config -> Book -> IO (Either LibriError ())
deleteBook cfg book = do
  dir <- getDataDir cfg
  let booksDir = dir </> "books"
      filename = bookFilename book
      path = booksDir </> filename
  exists <- doesFileExist path
  if not exists
    then pure $ Left $ BookNotFound (_bookId book)
    else do
      result <- try $ removeFile path
      case result of
        Left (e :: IOError) -> pure $ Left $ ParseError path (show e)
        Right () -> pure $ Right ()

-- | Load configuration from YAML file
loadConfig :: FilePath -> IO (Either LibriError Config)
loadConfig path = do
  expanded <- expandPath path
  exists <- doesFileExist expanded
  if not exists
    then pure $ Right defaultConfig
    else do
      result <- decodeFileEither expanded
      case result of
        Left err -> pure $ Left $ ParseError expanded (show err)
        Right cfg -> pure $ Right cfg

-- | Save configuration to YAML file
saveConfig :: FilePath -> Config -> IO (Either LibriError ())
saveConfig path cfg = do
  expanded <- expandPath path
  result <- try $ encodeFileAtomic expanded cfg
  case result of
    Left (e :: IOError) -> pure $ Left $ ParseError expanded (show e)
    Right () -> pure $ Right ()

-- | Load locations from YAML file
loadLocations :: Config -> IO (Either LibriError [Location])
loadLocations cfg = do
  dir <- getDataDir cfg
  let path = dir </> "locations.yaml"
  exists <- doesFileExist path
  if not exists
    then pure $ Right []
    else do
      result <- decodeFileEither path
      case result of
        Left err -> pure $ Left $ ParseError path (show err)
        Right locs -> pure $ Right locs

-- | Save locations to YAML file
saveLocations :: Config -> [Location] -> IO (Either LibriError ())
saveLocations cfg locs = do
  dir <- getDataDir cfg
  let path = dir </> "locations.yaml"
  result <- try $ encodeFileAtomic path locs
  case result of
    Left (e :: IOError) -> pure $ Left $ ParseError path (show e)
    Right () -> pure $ Right ()
