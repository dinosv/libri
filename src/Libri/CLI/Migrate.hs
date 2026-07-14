module Libri.CLI.Migrate
  ( MigrationStep (..)
  , planMigration
  , migrateBook
  , runMigrateIds
  ) where

import Control.Exception (IOException, catch, try)
import Control.Monad (forM, forM_, unless)
import Data.Aeson (Value (..))
import Data.Char (toLower)
import Data.List (isSuffixOf)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, mapMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import Libri.Storage.Yaml (encodeFileAtomic, getDataDir, loadBook)
import Libri.Types
import System.Directory (listDirectory, removeFile)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (hFlush, hPutStrLn, stderr, stdout)

-- | One planned change: a book together with its current file and
-- the (possibly re-identified) book it becomes
data MigrationStep = MigrationStep
  { msPath :: FilePath      -- current file
  , msOld :: Book           -- as loaded
  , msNew :: Book           -- with UUID id and provenance field
  }

-- | Does this book already have a UUID id?
hasUuidId :: Book -> Bool
hasUuidId = isJust . UUID.fromText . _bookId

-- | Re-identify a book: mint the given UUID, keep the old id as
-- identifier:calibre provenance (unless one is already recorded).
-- Books that already have a UUID id are returned unchanged.
migrateBook :: T.Text -> Book -> Book
migrateBook newId book
  | hasUuidId book = book
  | otherwise =
      book
        { _bookId = newId
        , _custom = Map.insertWith (\_ old -> old)
            "identifier:calibre" (String (_bookId book))
            (_custom book)
        }

-- | Which loaded books need work: a non-UUID id, or a stale filename
planMigration :: [(FilePath, Book)] -> [(FilePath, Book)]
planMigration loaded =
  [ (path, book)
  | (path, book) <- loaded
  , not (hasUuidId book) || not (bookFilename book `isSuffixOf` path)
  ]

-- | Migrate all books to UUID ids and canonical slug filenames
runMigrateIds :: Config -> IO ()
runMigrateIds cfg = do
  dir <- getDataDir cfg
  let booksDir = dir </> "books"
  files <- listDirectory booksDir
    `catch` \(_ :: IOException) -> pure []
  let yamlFiles = [f | f <- files, ".yaml" `isSuffixOf` f]
  loadedResults <- forM yamlFiles $ \f -> do
    let path = booksDir </> f
    result <- loadBook path
    pure $ either (const Nothing) (Just . (path,)) result
  let loaded = mapMaybe id loadedResults
      unreadable = length yamlFiles - length loaded
      todo = planMigration loaded

  unless (unreadable == 0) $
    hPutStrLn stderr $ "Warning: " <> show unreadable
      <> " unreadable files will be left untouched (run --doctor for details)"

  if null todo
    then TIO.putStrLn "Nothing to migrate: all books have UUID IDs and canonical filenames."
    else do
      steps <- forM todo $ \(path, book) -> do
        uuid <- UUID.toText <$> UUID.nextRandom
        let newBook' = migrateBook uuid book
        pure MigrationStep { msPath = path, msOld = book, msNew = newBook' }

      TIO.putStrLn $ "Migration plan (" <> T.pack (show (length steps)) <> " books):\n"
      forM_ steps $ \MigrationStep{..} -> do
        let newPath = booksDir </> bookFilename msNew
        TIO.putStrLn $ "  " <> (_title msOld)
        if _bookId msOld == _bookId msNew
          then TIO.putStrLn "    id unchanged (filename update only)"
          else TIO.putStrLn $ "    id: " <> _bookId msOld <> " -> " <> _bookId msNew
        putStrLn $ "    file: " <> msPath <> " -> " <> newPath

      TIO.putStrLn "\nCommit your data directory before proceeding, so this is easy to undo."
      TIO.putStr "Migrate now? [y/N] "
      hFlush stdout
      answer <- (Just <$> getLine) `catch` \(_ :: IOException) -> pure Nothing
      case map toLower <$> answer of
        Just a | a `elem` ["y", "yes"] -> do
          results <- forM steps $ \step -> do
            let newPath = booksDir </> bookFilename (msNew step)
            result <- try $ do
              encodeFileAtomic newPath (msNew step)
              unless (newPath == msPath step) $ removeFile (msPath step)
            pure (msNew step, result :: Either IOException ())
          let failures = [(b, e) | (b, Left e) <- results]
          forM_ failures $ \(b, e) ->
            hPutStrLn stderr $ "Error migrating '" <> T.unpack (_title b) <> "': " <> show e
          TIO.putStrLn $ "Migrated " <> T.pack (show (length results - length failures))
            <> " of " <> T.pack (show (length results)) <> " books."
          unless (null failures) exitFailure
        _ -> TIO.putStrLn "Migration cancelled."
