module Libri.CLI.Commands
  ( -- * Command Types
    Command (..)
  , Options (..)
  , AddOpts (..)
  , applyAddOpts
    -- * Parsing
  , parseOptions
  , optsParser
    -- * Execution
  , runCommand
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, catch, try)
import Control.Monad (forM, forM_, when)
import Data.Char (toLower)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Lens.Micro ((&), (.~), (^.))
import Libri.CLI.BatchImport (parseIsbnFile, FetchResult(..), BatchResults(..), categorizeResults, normalizeISBN, ImportChoice(..), parseImportChoice)
import Libri.CLI.Doctor (runDoctor)
import Libri.CLI.Enrich (runEnrich)
import Libri.CLI.Migrate (runMigrateIds)
import Libri.CLI.Tags (runTagRename, runTagDelete)
import Libri.ISBN.OpenLibrary (fetchByISBN, fetchByISBNWith, newISBNManager)
import Network.HTTP.Client (Manager)
import Libri.Search.Fuzzy (searchBooks)
import Libri.Storage.CalibreImport (importFromCalibre, saveImportedBooks)
import Libri.Storage.Index (BookIndex, buildIndex, lookupByISBN, lookupById)
import Libri.Storage.Yaml
import Libri.Types
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.IO (hFlush, hPutStrLn, stderr, stdout)
import Text.Read (readMaybe)

-- | CLI command to execute
data Command
  = CmdTUI                          -- ^ Launch TUI (default)
  | CmdAdd AddOpts                  -- ^ Add a new book
  | CmdSearch Text                  -- ^ Search for books
  | CmdMove MoveOpts                -- ^ Move book to location
  | CmdLocations                    -- ^ List all locations
  | CmdImportCalibre FilePath       -- ^ Import from Calibre
  | CmdImportIsbnTxt FilePath       -- ^ Batch import from ISBN text file
  | CmdList                         -- ^ List all books
  | CmdShow Text                    -- ^ Show book details
  | CmdDelete Text                  -- ^ Delete a book
  | CmdVersion                      -- ^ Show version
  | CmdEnrich                       -- ^ Enrich books from OpenLibrary
  | CmdDoctor                       -- ^ Collection integrity report
  | CmdMigrateIds                   -- ^ Migrate to UUID ids/slug filenames
  | CmdTagRename Text Text          -- ^ Rename/merge a tag
  | CmdTagDelete Text               -- ^ Delete a tag everywhere
  deriving (Show, Eq)

-- | Options for adding a book
data AddOpts = AddOpts
  { addISBN :: Maybe Text
  , addTitle :: Maybe Text
  , addAuthors :: [Text]
  , addLocation :: Maybe Text
  , addTags :: [Text]
  }
  deriving (Show, Eq)

-- | Options for moving a book
data MoveOpts = MoveOpts
  { moveBookId :: Text              -- ^ Book ID or ISBN
  , moveTo :: Text                  -- ^ Target location
  }
  deriving (Show, Eq)

-- | Full command-line options
data Options = Options
  { optConfigPath :: Maybe FilePath  -- ^ Explicit --config, if given
  , optCommand :: Command
  }
  deriving (Show)

-- | Parse command-line options
parseOptions :: IO Options
parseOptions = execParser opts
  where
    opts = info (optsParser <**> helper)
      ( fullDesc
     <> progDesc "Manage your physical book collection"
     <> header "libri - a TUI/CLI book collection manager"
      )

-- | Options parser
optsParser :: Parser Options
optsParser = Options
  <$> optional (strOption
      ( long "config"
     <> short 'c'
     <> metavar "PATH"
     <> help ("Path to configuration file (default: " <> defaultConfigPath <> ")")
      ))
  <*> commandParser

-- | Command parser
commandParser :: Parser Command
commandParser =
  -- Default to TUI if no flags given
  fromMaybe CmdTUI <$> optional
    ( addCommand
  <|> searchCommand
  <|> moveCommand
  <|> locationsCommand
  <|> importCommand
  <|> importIsbnTxtCommand
  <|> listCommand
  <|> showCommand
  <|> deleteCommand
  <|> versionCommand
  <|> enrichCommand
  <|> doctorCommand
  <|> migrateIdsCommand
  <|> tagRenameCommand
  <|> tagDeleteCommand
    )

addCommand :: Parser Command
addCommand = flag' () (long "add" <> short 'a' <> help "Add a new book")
  *> (CmdAdd <$> addOptsParser)

addOptsParser :: Parser AddOpts
addOptsParser = AddOpts
  <$> optional (strOption
      ( long "isbn"
     <> short 'i'
     <> metavar "ISBN"
     <> help "ISBN to lookup"
      ))
  <*> optional (strOption
      ( long "title"
     <> short 't'
     <> metavar "TITLE"
     <> help "Book title"
      ))
  <*> many (strOption
      ( long "author"
     <> metavar "AUTHOR"
     <> help "Book author (can be repeated)"
      ))
  <*> optional (strOption
      ( long "location"
     <> short 'l'
     <> metavar "LOCATION"
     <> help "Physical location"
      ))
  <*> many (strOption
      ( long "tag"
     <> metavar "TAG"
     <> help "Book tag (can be repeated)"
      ))

searchCommand :: Parser Command
searchCommand = CmdSearch <$> strOption
  ( long "search"
 <> short 's'
 <> metavar "QUERY"
 <> help "Search for books"
  )

moveCommand :: Parser Command
moveCommand = flag' () (long "move" <> short 'm' <> help "Move book to location")
  *> (CmdMove <$> moveOptsParser)

moveOptsParser :: Parser MoveOpts
moveOptsParser = MoveOpts
  <$> strOption
      ( long "book"
     <> short 'b'
     <> metavar "ID"
     <> help "Book ID or ISBN"
      )
  <*> strOption
      ( long "to"
     <> metavar "LOCATION"
     <> help "Target location"
      )

locationsCommand :: Parser Command
locationsCommand = flag' CmdLocations
  ( long "locations"
 <> help "List all locations"
  )

importCommand :: Parser Command
importCommand = CmdImportCalibre <$> strOption
  ( long "import-calibre"
 <> metavar "PATH"
 <> help "Import from Calibre library"
  )

importIsbnTxtCommand :: Parser Command
importIsbnTxtCommand = CmdImportIsbnTxt <$> strOption
  ( long "import-isbn-txt"
 <> metavar "FILE"
 <> help "Import books from text file with ISBNs (one per line)"
  )

listCommand :: Parser Command
listCommand = flag' CmdList
  ( long "list"
 <> help "List all books"
  )

showCommand :: Parser Command
showCommand = CmdShow <$> strOption
  ( long "show"
 <> metavar "ID"
 <> help "Show book details"
  )

deleteCommand :: Parser Command
deleteCommand = CmdDelete <$> strOption
  ( long "delete"
 <> metavar "ID"
 <> help "Delete a book"
  )

versionCommand :: Parser Command
versionCommand = flag' CmdVersion
  ( long "version"
 <> short 'v'
 <> help "Show version"
  )

enrichCommand :: Parser Command
enrichCommand = flag' CmdEnrich
  ( long "enrich"
 <> help "Enrich books with missing tags/descriptions from OpenLibrary"
  )

doctorCommand :: Parser Command
doctorCommand = flag' CmdDoctor
  ( long "doctor"
 <> help "Check collection integrity (read-only)"
  )

migrateIdsCommand :: Parser Command
migrateIdsCommand = flag' CmdMigrateIds
  ( long "migrate-ids"
 <> help "Migrate books to UUID IDs and title-based filenames"
  )

tagRenameCommand :: Parser Command
tagRenameCommand = CmdTagRename
  <$> strOption
      ( long "tag-rename"
     <> metavar "OLD"
     <> help "Rename a tag across the collection (with --to)"
      )
  <*> strOption
      ( long "to"
     <> metavar "NEW"
     <> help "New tag name"
      )

tagDeleteCommand :: Parser Command
tagDeleteCommand = CmdTagDelete <$> strOption
  ( long "tag-delete"
 <> metavar "TAG"
 <> help "Remove a tag from every book"
  )

-- | Run a CLI command
runCommand :: Config -> Command -> IO ()
runCommand cfg cmd = case cmd of
  CmdTUI -> pure ()  -- Handled in Main.hs

  CmdVersion -> putStrLn "libri version 0.1.0.0"

  CmdAdd opts -> runAdd cfg opts

  CmdSearch query -> runSearch cfg query

  CmdMove opts -> runMove cfg opts

  CmdLocations -> runLocations cfg

  CmdImportCalibre path -> runImportCalibre cfg path

  CmdImportIsbnTxt path -> runImportIsbnTxt cfg path

  CmdList -> runList cfg

  CmdShow bid -> runShow cfg bid

  CmdDelete bid -> runDelete cfg bid

  CmdEnrich -> runEnrich cfg

  CmdDoctor -> runDoctor cfg

  CmdMigrateIds -> runMigrateIds cfg

  CmdTagRename old new -> runTagRename cfg old new

  CmdTagDelete tag -> runTagDelete cfg tag

-- | Load books, printing a warning for any unreadable files
loadBooksReporting :: Config -> IO [Book]
loadBooksReporting cfg = do
  (errs, bks) <- loadBooksWithErrors cfg
  forM_ errs $ \(path, err) ->
    hPutStrLn stderr $ "Warning: skipping unreadable book file " <> path <> ": " <> show err
  pure bks

-- | Read a line from stdin, returning Nothing on EOF or closed stdin
-- so non-interactive use fails gracefully instead of crashing
readLineSafe :: IO (Maybe String)
readLineSafe = (Just <$> getLine) `catch` \(_ :: IOException) -> pure Nothing

-- | Apply the command-line options of --add to a looked-up (or blank)
-- book. The ISBN given is kept even when the lookup failed.
applyAddOpts :: AddOpts -> Book -> Book
applyAddOpts opts book = book
  & maybe id (\t -> title .~ t) (addTitle opts)
  & (if null (addAuthors opts) then id else authors .~ addAuthors opts)
  & location .~ addLocation opts
  & (if null (addTags opts) then id else tags .~ addTags opts)
  & (case (book ^. isbn, addISBN opts) of
       (Nothing, Just i) -> isbn .~ Just (normalizeISBN i)
       _ -> id)

-- | Add a new book
runAdd :: Config -> AddOpts -> IO ()
runAdd cfg opts = do
  book <- case addISBN opts of
    Just isbnVal -> do
      TIO.putStrLn $ "Looking up ISBN: " <> isbnVal
      result <- fetchByISBN isbnVal
      case result of
        Left err -> do
          hPutStrLn stderr $ "ISBN lookup failed: " <> show err
          -- Fall back to manual entry
          newBook
        Right b -> pure b
    Nothing -> newBook

  let book' = applyAddOpts opts book

  -- Validate
  when (T.null (book' ^. title)) $ do
    hPutStrLn stderr "Error: Book must have a title"
    exitFailure

  -- Refuse to silently overwrite an existing book with the same ID/ISBN
  existing <- loadBooksReporting cfg
  let idx = buildIndex existing
      dup = lookupById (book' ^. bookId) idx
        <|> (case book' ^. isbn of
               Just i -> lookupByISBN i idx
               Nothing -> Nothing)
  case dup of
    Just old -> do
      hPutStrLn stderr $ "Error: This book already exists: '"
        <> T.unpack (old ^. title) <> "' (ID: " <> T.unpack (old ^. bookId) <> ")"
      hPutStrLn stderr "Edit the existing entry instead of re-adding it."
      exitFailure
    Nothing -> pure ()

  -- Save
  result <- saveBook cfg book'
  case result of
    Left err -> do
      hPutStrLn stderr $ "Error saving book: " <> show err
      exitFailure
    Right () -> do
      TIO.putStrLn $ "Added: " <> (book' ^. title)
      TIO.putStrLn $ "ID: " <> (book' ^. bookId)

-- | Search for books
runSearch :: Config -> Text -> IO ()
runSearch cfg query = do
  bks <- loadBooksReporting cfg
  let threshold = _fuzzyThreshold cfg
      results = searchBooks threshold query bks
  if null results
    then TIO.putStrLn "No books found."
    else do
      TIO.putStrLn $ "Found " <> T.pack (show (length results)) <> " book(s):\n"
      forM_ results $ \book -> do
        TIO.putStrLn $ "  " <> (book ^. title)
        TIO.putStrLn $ "    by " <> T.intercalate ", " (book ^. authors)
        case book ^. location of
          Just loc -> TIO.putStrLn $ "    Location: " <> loc
          Nothing -> pure ()
        TIO.putStrLn ""

-- | Move a book to a new location
runMove :: Config -> MoveOpts -> IO ()
runMove cfg opts = do
  bks <- loadBooksReporting cfg
  let idx = buildIndex bks
      mBook = lookupById (moveBookId opts) idx
          <|> lookupByISBN (moveBookId opts) idx
  case mBook of
    Nothing -> do
      hPutStrLn stderr $ "Book not found: " <> T.unpack (moveBookId opts)
      exitFailure
    Just book -> do
      let book' = book & location .~ Just (moveTo opts)
      result <- saveBook cfg book'
      case result of
        Left err -> do
          hPutStrLn stderr $ "Error saving book: " <> show err
          exitFailure
        Right () -> do
          TIO.putStrLn $ "Moved '" <> (book ^. title) <> "' to " <> moveTo opts

-- | List all locations
runLocations :: Config -> IO ()
runLocations cfg = do
  result <- loadLocations cfg
  case result of
    Left err -> do
      hPutStrLn stderr $ "Error loading locations: " <> show err
      exitFailure
    Right locs -> do
      TIO.putStrLn "Locations:"
      forM_ locs $ \loc ->
        TIO.putStrLn $ "  - " <> loc

-- | Import from Calibre
runImportCalibre :: Config -> FilePath -> IO ()
runImportCalibre cfg path = do
  TIO.putStrLn $ "Importing from Calibre library: " <> T.pack path
  result <- importFromCalibre path
  case result of
    Left err -> do
      hPutStrLn stderr $ "Import failed: " <> show err
      exitFailure
    Right bks -> do
      TIO.putStrLn $ "Found " <> T.pack (show (length bks)) <> " books"
      results <- saveImportedBooks cfg bks

      let successes = length [() | Right () <- results]
          failures = length [() | Left _ <- results]

      forM_ (zip bks results) $ \(book, saveResult) ->
        case saveResult of
          Left err ->
            hPutStrLn stderr $ "Error saving '" <> T.unpack (book ^. title) <> "': " <> show err
          Right () ->
            TIO.putStrLn $ "  Imported: " <> (book ^. title)

      TIO.putStrLn ""
      TIO.putStrLn $ "Import complete! " <> T.pack (show successes) <> " books saved successfully"
      when (failures > 0) $
        TIO.putStrLn $ "  " <> T.pack (show failures) <> " books failed to save"

-- | List all books
runList :: Config -> IO ()
runList cfg = do
  bks <- loadBooksReporting cfg
  do
      TIO.putStrLn $ "Total: " <> T.pack (show (length bks)) <> " book(s)\n"
      forM_ bks $ \book -> do
        TIO.putStrLn $ (book ^. title)
        TIO.putStrLn $ "  ID: " <> (book ^. bookId)
        when (not $ null $ book ^. authors) $
          TIO.putStrLn $ "  Authors: " <> T.intercalate ", " (book ^. authors)
        case book ^. location of
          Just loc -> TIO.putStrLn $ "  Location: " <> loc
          Nothing -> pure ()
        TIO.putStrLn ""

-- | Show book details
runShow :: Config -> Text -> IO ()
runShow cfg bookIdText = do
  bks <- loadBooksReporting cfg
  let idx = buildIndex bks
      mBook = lookupById bookIdText idx
          <|> lookupByISBN bookIdText idx
  case mBook of
    Nothing -> do
      hPutStrLn stderr $ "Book not found: " <> T.unpack bookIdText
      exitFailure
    Just book -> printBookDetails book

-- | Print detailed book information
printBookDetails :: Book -> IO ()
printBookDetails book = do
  TIO.putStrLn $ "Title: " <> (book ^. title)
  TIO.putStrLn $ "ID: " <> (book ^. bookId)
  case book ^. isbn of
    Just i -> TIO.putStrLn $ "ISBN: " <> i
    Nothing -> pure ()
  when (not $ null $ book ^. authors) $
    TIO.putStrLn $ "Authors: " <> T.intercalate ", " (book ^. authors)
  case book ^. series of
    Just s -> do
      TIO.putStr $ "Series: " <> s
      case book ^. seriesIndex of
        Just idx -> TIO.putStrLn $ " #" <> T.pack (show idx)
        Nothing -> TIO.putStrLn ""
    Nothing -> pure ()
  case book ^. publisher of
    Just p -> TIO.putStrLn $ "Publisher: " <> p
    Nothing -> pure ()
  case book ^. published of
    Just d -> TIO.putStrLn $ "Published: " <> T.pack (show d)
    Nothing -> pure ()
  when (not $ null $ book ^. tags) $
    TIO.putStrLn $ "Tags: " <> T.intercalate ", " (book ^. tags)
  case book ^. rating of
    Just r -> TIO.putStrLn $ "Rating: " <> T.replicate r "★" <> T.replicate (5 - r) "☆"
    Nothing -> pure ()
  case book ^. location of
    Just loc -> TIO.putStrLn $ "Location: " <> loc
    Nothing -> pure ()
  case book ^. comments of
    Just c -> do
      TIO.putStrLn "Comments:"
      TIO.putStrLn $ "  " <> T.take 200 c
    Nothing -> pure ()

-- | Delete a book (asks for confirmation)
runDelete :: Config -> Text -> IO ()
runDelete cfg bookIdText = do
  bks <- loadBooksReporting cfg
  let idx = buildIndex bks
      mBook = lookupById bookIdText idx
          <|> lookupByISBN bookIdText idx
  case mBook of
    Nothing -> do
      hPutStrLn stderr $ "Book not found: " <> T.unpack bookIdText
      exitFailure
    Just book -> do
      TIO.putStr $ "Delete '" <> (book ^. title) <> "' (ID: " <> (book ^. bookId) <> ")? [y/N] "
      hFlush stdout
      answer <- readLineSafe
      case map toLower <$> answer of
        Just a | a `elem` ["y", "yes"] -> do
          deleteResult <- deleteBook cfg book
          case deleteResult of
            Left err -> do
              hPutStrLn stderr $ "Error deleting book: " <> show err
              exitFailure
            Right () ->
              TIO.putStrLn $ "Deleted: " <> (book ^. title)
        _ -> TIO.putStrLn "Cancelled."

-- | Import books from a text file containing ISBNs
runImportIsbnTxt :: Config -> FilePath -> IO ()
runImportIsbnTxt cfg path = do
  -- Phase 1: Read and parse file
  TIO.putStrLn $ "Reading ISBNs from: " <> T.pack path
  contentResult <- try (TIO.readFile path) :: IO (Either IOException Text)
  content <- case contentResult of
    Left e -> do
      hPutStrLn stderr $ "Error reading " <> path <> ": " <> show e
      exitFailure
    Right c -> pure c
  let isbns = parseIsbnFile content

  when (null isbns) $ do
    TIO.putStrLn "No ISBNs found in file."
    exitSuccess

  TIO.putStrLn $ "Found " <> tshow (length isbns) <> " ISBNs to process.\n"

  -- Load existing books for duplicate detection
  existingBooks <- loadBooksReporting cfg
  let idx = buildIndex existingBooks

  -- Phase 2: Fetch with progress (reuse a single HTTP manager)
  mgr <- newISBNManager
  results <- forM (zip [1..] isbns) $ \(n :: Int, isbnRaw) -> do
    TIO.putStr $ "Processing " <> tshow n <> "/" <> tshow (length isbns)
              <> ": " <> isbnRaw <> "... "
    hFlush stdout
    result <- fetchAndCategorize mgr idx isbnRaw
    printResultStatus result
    -- 1.5 second delay between requests (rate limiting)
    when (n < length isbns) $ threadDelay 1500000
    pure result

  -- Phase 3: Categorize and display
  let categorized = categorizeResults results
  TIO.putStrLn ""
  displayBatchResults categorized

  -- Phase 4: User selection
  when (null (brNew categorized) && null (brDuplicates categorized)) $ do
    TIO.putStrLn "No books available to import."
    exitSuccess

  selection <- promptForSelection categorized

  -- Phase 5: Save selected
  case selection of
    Nothing -> TIO.putStrLn "Import cancelled."
    Just booksToSave -> do
      TIO.putStrLn $ "\nImporting " <> tshow (length booksToSave) <> " books...\n"
      saveResults <- forM booksToSave $ \book -> do
        saveResult <- saveBook cfg book
        case saveResult of
          Left err ->
            TIO.putStrLn $ "  ✗ " <> (book ^. title) <> " (Error: " <> T.pack (show err) <> ")"
          Right () ->
            TIO.putStrLn $ "  ✓ " <> (book ^. title)
        pure saveResult
      let saved = length [() | Right () <- saveResults]
          failedSaves = length booksToSave - saved
      TIO.putStrLn $ "\nImport complete! " <> tshow saved <> " books added to collection."
      when (failedSaves > 0) $
        TIO.putStrLn $ "  " <> tshow failedSaves <> " books failed to save"

-- | Helper to show Text values
tshow :: Show a => a -> Text
tshow = T.pack . show

-- | Fetch book and categorize against existing index
fetchAndCategorize :: Manager -> BookIndex -> Text -> IO FetchResult
fetchAndCategorize mgr idx isbnRaw = do
  let normalizedIsbn = normalizeISBN isbnRaw
  case lookupByISBN normalizedIsbn idx of
    Just existing -> do
      result <- fetchByISBNWith mgr isbnRaw
      case result of
        Right fetched -> pure $ FetchDuplicate fetched existing
        Left _ -> pure $ FetchDuplicate existing existing
    Nothing -> do
      result <- fetchByISBNWith mgr isbnRaw
      case result of
        Right book -> pure $ FetchSuccess book
        Left (ISBNNotFound _) -> pure $ FetchNotFound isbnRaw
        Left err -> pure $ FetchError isbnRaw (show err)

-- | Print status symbol for a fetch result
printResultStatus :: FetchResult -> IO ()
printResultStatus = \case
  FetchSuccess book -> TIO.putStrLn $ "✓ \"" <> (book ^. title) <> "\""
  FetchNotFound _ -> TIO.putStrLn "✗ Not found in OpenLibrary"
  FetchError _ err -> TIO.putStrLn $ "✗ Error: " <> T.pack err
  FetchDuplicate _ existing -> TIO.putStrLn $ "⚠ Duplicate (already in collection: \"" <> (existing ^. title) <> "\")"

-- | Display categorized batch results
displayBatchResults :: BatchResults -> IO ()
displayBatchResults BatchResults{..} = do
  TIO.putStrLn "═══════════════════════════════════════════════════════════════"
  TIO.putStrLn "                      IMPORT SUMMARY"
  TIO.putStrLn "═══════════════════════════════════════════════════════════════"
  TIO.putStrLn ""

  -- New books
  when (not $ null brNew) $ do
    TIO.putStrLn $ "NEW BOOKS (" <> tshow (length brNew) <> " found):"
    forM_ brNew $ \book -> do
      TIO.putStrLn $ "  • " <> (book ^. title)
      TIO.putStrLn $ "    Authors: " <> T.intercalate ", " (book ^. authors)
      case book ^. isbn of
        Just i -> TIO.putStrLn $ "    ISBN: " <> i
        Nothing -> pure ()
      case book ^. publisher of
        Just p -> TIO.putStrLn $ "    Publisher: " <> p
        Nothing -> pure ()
      when (not $ null $ book ^. tags) $
        TIO.putStrLn $ "    Tags: " <> T.intercalate ", " (book ^. tags)
      case book ^. comments of
        Just c -> TIO.putStrLn $ "    Description: " <> T.take 100 c <> "..."
        Nothing -> pure ()
      TIO.putStrLn ""
    TIO.putStrLn ""

  -- Duplicates
  when (not $ null brDuplicates) $ do
    TIO.putStrLn $ "DUPLICATES (" <> tshow (length brDuplicates) <> " found):"
    forM_ brDuplicates $ \(fetched, existing) -> do
      TIO.putStrLn $ "  • " <> (fetched ^. title)
      TIO.putStrLn $ "    Already exists as: " <> (existing ^. bookId)
    TIO.putStrLn ""

  -- Not found
  when (not $ null brNotFound) $ do
    TIO.putStrLn $ "NOT FOUND (" <> tshow (length brNotFound) <> "):"
    forM_ brNotFound $ \isbnVal ->
      TIO.putStrLn $ "  - " <> isbnVal
    TIO.putStrLn ""

  -- Errors
  when (not $ null brErrors) $ do
    TIO.putStrLn $ "ERRORS (" <> tshow (length brErrors) <> "):"
    forM_ brErrors $ \(isbnVal, err) ->
      TIO.putStrLn $ "  - " <> isbnVal <> ": " <> T.pack err
    TIO.putStrLn ""

  TIO.putStrLn "═══════════════════════════════════════════════════════════════"

-- | Prompt user for selection
promptForSelection :: BatchResults -> IO (Maybe [Book])
promptForSelection BatchResults{..}
  | numNew == 0 && numDups == 0 = pure Nothing
  | otherwise = do
      TIO.putStrLn "\nImport options:"
      when (numNew > 0) $
        TIO.putStrLn $ "  [a] Import all new books (" <> tshow numNew <> ")"
      when (numDups > 0) $
        TIO.putStrLn $ "  [d] Import all including duplicates (" <> tshow totalAvailable <> ")"
      TIO.putStrLn "  [s] Select specific books to import"
      TIO.putStrLn "  [n] Cancel - don't import anything"
      TIO.putStrLn ""
      askChoice
  where
    askChoice = do
      TIO.putStr "Choice [a/d/s/n]: "
      hFlush stdout
      mChoice <- readLineSafe
      case parseImportChoice . T.pack <$> mChoice of
        Nothing -> do
          TIO.putStrLn "No input available. Cancelling."
          pure Nothing
        Just (Just ImportNew) -> pure $ Just brNew
        Just (Just ImportAll) -> pure $ Just (brNew ++ map fst brDuplicates)
        Just (Just ImportSelect) -> selectSpecificBooks brNew brDuplicates
        Just (Just ImportCancel) -> pure Nothing
        Just Nothing -> do
          TIO.putStrLn "Please answer a, d, s or n."
          askChoice
    numNew = length brNew
    numDups = length brDuplicates
    totalAvailable = numNew + numDups

-- | Allow user to select specific books
selectSpecificBooks :: [Book] -> [(Book, Book)] -> IO (Maybe [Book])
selectSpecificBooks newBooks duplicates = do
  let allBooks' = newBooks ++ map fst duplicates
      numbered = zip [1..] allBooks'

  TIO.putStrLn "\nAvailable books:"
  forM_ numbered $ \(n :: Int, book) -> do
    let isDup = any (\(b, _) -> book == b) duplicates
        marker = if isDup then " (duplicate)" else ""
    TIO.putStrLn $ "  [" <> tshow n <> "] " <> (book ^. title) <> marker

  TIO.putStrLn "\nEnter numbers separated by spaces (e.g., \"1 3 5\"), or 'all' for all, 'none' to cancel:"
  TIO.putStr "> "
  hFlush stdout

  mInput <- readLineSafe
  case map toLower <$> mInput of
    Nothing -> pure Nothing
    Just "all" -> pure $ Just allBooks'
    Just "none" -> pure Nothing
    Just "" -> pure Nothing
    Just input -> do
      let nums = mapMaybe (readMaybe :: String -> Maybe Int) $ words input
          selected = [book | (n, book) <- numbered, n `elem` nums]
      if null selected
        then do
          TIO.putStrLn "No valid selections. Cancelling."
          pure Nothing
        else pure $ Just selected
