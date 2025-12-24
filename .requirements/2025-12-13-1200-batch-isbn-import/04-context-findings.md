# Codebase Analysis Findings - Batch ISBN Import

**Analysis Date:** 2025-12-13
**Mode:** READ-ONLY (no code was modified)

---

## Architecture Overview

- **Language:** Haskell with GHC 9.6.6
- **CLI Parser:** optparse-applicative
- **ISBN Lookup:** OpenLibrary API (`src/Libri/ISBN/OpenLibrary.hs`)
- **Storage:** YAML files in user data directory
- **Index:** In-memory index with ISBN lookup support

---

## Similar Features Found

### 1. Single ISBN Import (`runAdd`)
**File:** `src/Libri/CLI/Commands.hs:229-263`

```haskell
runAdd :: Config -> AddOpts -> IO ()
runAdd cfg opts = do
  book <- case addISBN opts of
    Just isbn -> do
      TIO.putStrLn $ "Looking up ISBN: " <> isbn
      result <- fetchByISBN isbn
      case result of
        Left err -> do
          hPutStrLn stderr $ "ISBN lookup failed: " <> show err
          newBook  -- Fall back to manual entry
        Right b -> pure b
    Nothing -> newBook
```

**Pattern:** Uses `fetchByISBN` for single lookup, handles errors gracefully.

### 2. Calibre Batch Import (`runImportCalibre`)
**File:** `src/Libri/CLI/Commands.hs:332-350`

```haskell
runImportCalibre :: Config -> FilePath -> IO ()
runImportCalibre cfg path = do
  TIO.putStrLn $ "Importing from Calibre library: " <> T.pack path
  result <- importFromCalibre path
  case result of
    Left err -> do
      hPutStrLn stderr $ "Import failed: " <> show err
      exitFailure
    Right books -> do
      TIO.putStrLn $ "Found " <> T.pack (show (length books)) <> " books"
      forM_ books $ \book -> do
        saveResult <- saveBook cfg book
        case saveResult of
          Left err ->
            hPutStrLn stderr $ "Error saving '" <> T.unpack (book ^. title) <> "': " <> show err
          Right () ->
            TIO.putStrLn $ "  Imported: " <> (book ^. title)
      TIO.putStrLn "\nImport complete!"
```

**Pattern:** Batch import with per-item progress and error handling. This is the closest pattern to what we need.

### 3. Duplicate Detection via Index
**File:** `src/Libri/Storage/Index.hs:113-114`

```haskell
lookupByISBN :: Text -> BookIndex -> Maybe Book
lookupByISBN i idx = Map.lookup i (_byISBN idx)
```

**Usage:** Can check if ISBN already exists before importing.

---

## Patterns to Follow

### Command Definition Pattern
```haskell
-- In Command data type
| CmdImportBatch FilePath       -- ^ Import from ISBN file

-- Parser
importBatchCommand :: Parser Command
importBatchCommand = CmdImportBatch <$> strOption
  ( long "import-batch"
 <> metavar "FILE"
 <> help "Import books from file with ISBNs (one per line)"
  )
```

### Batch Processing Pattern (from runImportCalibre)
```haskell
forM_ items $ \item -> do
  result <- processItem item
  case result of
    Left err -> hPutStrLn stderr $ "Error: " <> show err
    Right () -> TIO.putStrLn $ "  Success: " <> itemName
```

---

## Files to Modify/Create

| File | Action | Description |
|------|--------|-------------|
| `src/Libri/CLI/Commands.hs` | Modify | Add `CmdImportBatch`, parser, and `runImportBatch` |
| `src/Libri/ISBN/OpenLibrary.hs` | Modify (optional) | Could add batch fetch with delay |
| `src/Libri/Types.hs` | Modify | Add new error type for batch import |

---

## Integration Points

1. **CLI Parser:** Add new command option in `commandParser`
2. **ISBN Lookup:** Reuse existing `fetchByISBN` from `Libri.ISBN.OpenLibrary`
3. **Duplicate Check:** Use `lookupByISBN` from `Libri.Storage.Index`
4. **Book Storage:** Reuse `saveBook` from `Libri.Storage.Yaml`
5. **Book Loading:** Use `loadBooks` to build index for duplicate check

---

## Error Types Available

From `src/Libri/Types.hs:202-210`:
```haskell
data LibriError
  = FileNotFound FilePath
  | ParseError FilePath String
  | NetworkError String
  | ISBNNotFound Text
  | BookNotFound BookId
  | InvalidISBN Text
  | CalibreImportError String
```

`ISBNNotFound` already exists - can reuse for batch import failures.

---

## Implementation Approach

### Phase 1: Read & Parse File
```haskell
-- Read file, filter empty lines and comments
isbns <- T.lines <$> TIO.readFile path
let validISBNs = filter (not . T.null . T.strip)
               $ filter (not . T.isPrefixOf "#") isbns
```

### Phase 2: Fetch with Delay
```haskell
import Control.Concurrent (threadDelay)

forM isbns $ \isbn -> do
  result <- fetchByISBN isbn
  threadDelay 1500000  -- 1.5 second delay
  pure (isbn, result)
```

### Phase 3: Review & Confirm (User Requirement)
- Show list of fetched books with metadata
- Show list of failed ISBNs
- Show list of duplicates
- Prompt user to confirm before saving

### Phase 4: Save
```haskell
forM_ confirmedBooks $ \book -> do
  saveBook cfg book
```

---

## Technical Constraints

1. **Rate Limiting:** OpenLibrary recommends 1 request/second max
2. **Network Errors:** Must handle timeouts, connection failures
3. **File Encoding:** Assume UTF-8 for ISBN file
4. **ISBN Formats:** Support both ISBN-10 and ISBN-13, with/without dashes

---

## Best Practices

1. **Progress Feedback:** Show "Processing X of Y: ISBN..."
2. **Graceful Degradation:** Continue on individual failures
3. **Summary Report:** Show success/fail counts at end
4. **Review Step:** User requested ability to verify before commit
5. **Duplicate Warning:** Clear indication of which ISBNs already exist

---

## Recommended Approach

Create a two-phase CLI workflow:

1. **Fetch Phase:** `libri --import-batch file.txt`
   - Read ISBNs from file
   - Fetch metadata for each (with delay)
   - Check for duplicates
   - Display results for review
   - Prompt: "Import N books? [y/N/select]"

2. **Save Phase:** (after user confirmation)
   - Save selected books
   - Report final summary

This matches the user's requirement for "verificar que los registros están correctos antes de incorporarlos a la base".
