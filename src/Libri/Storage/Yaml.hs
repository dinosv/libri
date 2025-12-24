module Libri.Storage.Yaml
  ( -- * Loading
    loadBooks
  , loadBook
  , loadConfig
  , loadLocations
    -- * Saving
  , saveBook
  , saveConfig
  , saveLocations
  , deleteBook
    -- * Directory Management
  , initDataDir
  , getDataDir
  , expandPath
  ) where

import Control.Exception (try)
import Control.Monad (forM, when, void)
import Data.Aeson (Value)
import qualified Data.ByteString as BS
import Data.List (isSuffixOf)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Data.Yaml (decodeFileEither, encodeFile, ParseException)
import Lens.Micro ((&), (.~))
import Libri.Types
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getHomeDirectory
  , listDirectory
  , removeFile
  )
import System.FilePath ((</>), takeBaseName)

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

-- | Load all books from the data directory
loadBooks :: Config -> IO (Either LibriError [Book])
loadBooks cfg = do
  dir <- getDataDir cfg
  let booksDir = dir </> "books"
  exists <- doesDirectoryExist booksDir
  if not exists
    then pure $ Right []
    else do
      files <- listDirectory booksDir
      -- Filter out non-book YAML files
      let isBookFile f = ".yaml" `isSuffixOf` f && f /= "locations.yaml" && f /= "config.yaml"
          yamlFiles = filter isBookFile files
      results <- forM yamlFiles $ \file -> do
        loadBook (booksDir </> file)
      pure $ sequence results

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
  result <- try $ encodeFile path book'
  case result of
    Left (e :: IOError) -> pure $ Left $ ParseError path (show e)
    Right () -> pure $ Right ()

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
  result <- try $ encodeFile expanded cfg
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
  result <- try $ encodeFile path locs
  case result of
    Left (e :: IOError) -> pure $ Left $ ParseError path (show e)
    Right () -> pure $ Right ()
