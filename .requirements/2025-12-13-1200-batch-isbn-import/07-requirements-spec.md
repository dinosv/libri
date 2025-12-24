# Batch ISBN Import Feature

**Created:** 2025-12-13T12:00:00Z
**Status:** draft
**Last Updated:** 2025-12-13T12:30:00Z

---

## Overview

Add a CLI command `--import-isbn-txt` that allows batch importing books by reading a text file containing ISBN numbers (one per line). The feature will:

1. Read ISBNs from a text file
2. Fetch metadata from OpenLibrary API (with rate limiting)
3. Check for duplicates against existing collection
4. Display results for user review before saving
5. Allow selective importing based on user choices

This addresses the need to quickly add multiple books to the collection without manually entering each ISBN individually.

---

## Implementation Strategy

### Recommended Skill
**Skill:** `superpowers:test-driven-development`

**Rationale:**
This feature involves:
- New CLI command parsing (testable)
- File reading and parsing (testable)
- API integration with error handling (testable with mocks)
- Duplicate detection logic (testable)
- User interaction flow (integration testable)

TDD ensures each component works correctly before integration.

**To implement:** Use the TDD skill to build this feature incrementally.

---

## Requirements

### Functional Requirements

1. **FR1:** Read ISBN list from text file (one ISBN per line)
2. **FR2:** Skip empty lines and lines starting with `#` (comments)
3. **FR3:** Fetch book metadata from OpenLibrary for each ISBN
4. **FR4:** Apply 1.5 second delay between API requests (rate limiting)
5. **FR5:** Show verbose progress during fetch ("Processing 1/10: 978-...")
6. **FR6:** Detect ISBNs that already exist in collection (duplicates)
7. **FR7:** Display full metadata for review before saving:
   - ISBN, Title, Authors, Publisher, Year, Tags, Description (truncated)
8. **FR8:** Categorize results into: New books, Duplicates, Failed lookups
9. **FR9:** Allow user to select which books to import via prompt
10. **FR10:** Save selected books to collection
11. **FR11:** Show final summary (imported, skipped, failed counts)

### User Interaction Flow

```
$ libri --import-isbn-txt books.txt

Reading ISBNs from: books.txt
Found 10 ISBNs to process.

Processing 1/10: 978-0-13-468599-1... ✓ "The Pragmatic Programmer"
Processing 2/10: 978-0-596-51774-8... ✓ "JavaScript: The Good Parts"
Processing 3/10: 978-0-00-000000-0... ✗ Not found in OpenLibrary
Processing 4/10: 978-0-13-235088-4... ⚠ Duplicate (already in collection)
...

═══════════════════════════════════════════════════════════════
                      IMPORT SUMMARY
═══════════════════════════════════════════════════════════════

NEW BOOKS (7 found):
┌─────────────────┬────────────────────────────────┬─────────────────────┐
│ ISBN            │ Title                          │ Authors             │
├─────────────────┼────────────────────────────────┼─────────────────────┤
│ 978-0-13-468599 │ The Pragmatic Programmer       │ Hunt, Thomas        │
│ 978-0-596-51774 │ JavaScript: The Good Parts     │ Crockford, Douglas  │
│ ...             │ ...                            │ ...                 │
└─────────────────┴────────────────────────────────┴─────────────────────┘
  Publisher: Addison-Wesley | Year: 2019 | Tags: programming, software
  Description: A guide to pragmatic programming practices...

DUPLICATES (2 found):
┌─────────────────┬────────────────────────────────┬─────────────────────┐
│ ISBN            │ Title                          │ Existing ID         │
├─────────────────┼────────────────────────────────┼─────────────────────┤
│ 978-0-13-235088 │ Clean Code                     │ book-123            │
└─────────────────┴────────────────────────────────┴─────────────────────┘

NOT FOUND (1):
  - 978-0-00-000000-0

═══════════════════════════════════════════════════════════════

Import options:
  [a] Import all new books (7)
  [d] Import all including duplicates (9)
  [s] Select specific books to import
  [n] Cancel - don't import anything

Choice [a/d/s/n]: a

Importing 7 books...
  ✓ The Pragmatic Programmer
  ✓ JavaScript: The Good Parts
  ...

Import complete! 7 books added to collection.
```

---

## Technical Implementation

### Architecture Decision

Add new command following existing `--import-calibre` pattern. Create a two-phase workflow:
1. **Fetch phase:** Collect all data, categorize results
2. **Review phase:** Display and get user confirmation
3. **Save phase:** Persist selected books

### Files to Modify

| File | Changes |
|------|---------|
| `src/Libri/CLI/Commands.hs` | Add `CmdImportIsbnTxt`, parser, `runImportIsbnTxt` |
| `src/Libri/Types.hs` | (Optional) Add `BatchImportError` if needed |

### New Types

```haskell
-- Result of fetching a single ISBN
data FetchResult
  = FetchSuccess Book
  | FetchNotFound Text      -- ISBN not in OpenLibrary
  | FetchError Text String  -- ISBN + error message
  | FetchDuplicate Book Book  -- fetched book + existing book

-- Categorized batch results
data BatchResults = BatchResults
  { brNew :: [Book]           -- New books ready to import
  , brDuplicates :: [(Book, Book)]  -- (fetched, existing)
  , brNotFound :: [Text]      -- ISBNs not found
  , brErrors :: [(Text, String)]  -- ISBNs with errors
  }
```

### Command Parser

```haskell
importIsbnTxtCommand :: Parser Command
importIsbnTxtCommand = CmdImportIsbnTxt <$> strOption
  ( long "import-isbn-txt"
 <> metavar "FILE"
 <> help "Import books from text file with ISBNs (one per line)"
  )
```

### Core Implementation

```haskell
runImportIsbnTxt :: Config -> FilePath -> IO ()
runImportIsbnTxt cfg path = do
  -- Phase 1: Read and parse file
  content <- TIO.readFile path
  let isbns = parseIsbnFile content

  -- Phase 2: Fetch with progress
  TIO.putStrLn $ "Found " <> tshow (length isbns) <> " ISBNs to process.\n"
  existingBooks <- loadBooks cfg >>= either (const $ pure []) pure
  let idx = buildIndex existingBooks

  results <- forM (zip [1..] isbns) $ \(n, isbn) -> do
    TIO.putStr $ "Processing " <> tshow n <> "/" <> tshow (length isbns)
              <> ": " <> isbn <> "... "
    result <- fetchAndCategorize idx isbn
    printResultStatus result
    threadDelay 1500000  -- 1.5 sec delay
    pure result

  -- Phase 3: Categorize and display
  let categorized = categorizeResults results
  displayResults categorized

  -- Phase 4: User selection
  selection <- promptForSelection categorized

  -- Phase 5: Save selected
  saveSelected cfg selection

parseIsbnFile :: Text -> [Text]
parseIsbnFile content =
  filter (not . T.null)
  $ filter (not . T.isPrefixOf "#")
  $ map T.strip
  $ T.lines content

fetchAndCategorize :: BookIndex -> Text -> IO FetchResult
fetchAndCategorize idx isbn =
  case lookupByISBN (normalizeISBN isbn) idx of
    Just existing -> do
      -- It's a duplicate, but still fetch to show comparison
      result <- fetchByISBN isbn
      case result of
        Right fetched -> pure $ FetchDuplicate fetched existing
        Left _ -> pure $ FetchDuplicate existing existing  -- Use existing as placeholder
    Nothing -> do
      result <- fetchByISBN isbn
      case result of
        Right book -> pure $ FetchSuccess book
        Left (ISBNNotFound _) -> pure $ FetchNotFound isbn
        Left err -> pure $ FetchError isbn (show err)
```

### Integration Points

1. **Reuse `fetchByISBN`** from `Libri.ISBN.OpenLibrary`
2. **Reuse `lookupByISBN`** from `Libri.Storage.Index` for duplicate detection
3. **Reuse `saveBook`** from `Libri.Storage.Yaml`
4. **Reuse `loadBooks`** and `buildIndex` for existing collection

---

## Testing Strategy

### Unit Tests

```haskell
-- test/BatchImportSpec.hs

describe "parseIsbnFile" $ do
  it "parses one ISBN per line" $ do
    parseIsbnFile "978-0-13-468599-1\n978-0-596-51774-8"
      `shouldBe` ["978-0-13-468599-1", "978-0-596-51774-8"]

  it "skips empty lines" $ do
    parseIsbnFile "978-0-13-468599-1\n\n978-0-596-51774-8"
      `shouldBe` ["978-0-13-468599-1", "978-0-596-51774-8"]

  it "skips comment lines" $ do
    parseIsbnFile "# My books\n978-0-13-468599-1"
      `shouldBe` ["978-0-13-468599-1"]

  it "trims whitespace" $ do
    parseIsbnFile "  978-0-13-468599-1  "
      `shouldBe` ["978-0-13-468599-1"]

describe "categorizeResults" $ do
  it "separates new, duplicates, and not found" $ ...
```

### Integration Tests

- Test with mock OpenLibrary responses
- Test duplicate detection against test fixture books
- Test user prompt flow (if feasible)

---

## Edge Cases & Constraints

### Edge Cases to Handle

1. **Empty file:** Show "No ISBNs found in file" and exit
2. **File not found:** Show error and exit with code 1
3. **All ISBNs fail:** Still show summary, allow exit gracefully
4. **Network timeout:** Catch and report as error, continue with others
5. **Invalid ISBN format:** Try to normalize, report if still invalid
6. **Very long file:** Consider showing progress percentage

### Technical Constraints

1. **OpenLibrary Rate Limit:** Max 1 request/second recommended
2. **Terminal Width:** Truncate long titles/descriptions for display
3. **Memory:** For very large files (1000+ ISBNs), process in batches

### Security Considerations

1. **File Path:** Validate file exists, is readable, reasonable size
2. **ISBN Input:** Sanitize before using in API URL (already done in `fetchByISBN`)

---

## Acceptance Criteria

- [ ] `libri --import-isbn-txt file.txt` parses ISBNs from file
- [ ] Shows progress for each ISBN being fetched
- [ ] Respects 1.5 second delay between API calls
- [ ] Correctly identifies duplicates using existing collection
- [ ] Displays categorized results (new, duplicate, not found)
- [ ] Shows full metadata for each book in review
- [ ] Allows user to select import option (all/duplicates/select/none)
- [ ] Successfully saves selected books to collection
- [ ] Shows final summary with counts
- [ ] Handles errors gracefully (file not found, network issues)

---

## Implementation Checklist

- [ ] Add `CmdImportIsbnTxt FilePath` to `Command` data type
- [ ] Add `importIsbnTxtCommand` parser
- [ ] Add case for `CmdImportIsbnTxt` in `runCommand`
- [ ] Implement `parseIsbnFile` function
- [ ] Implement `FetchResult` and `BatchResults` types
- [ ] Implement `fetchAndCategorize` with duplicate detection
- [ ] Implement `displayResults` with full metadata formatting
- [ ] Implement `promptForSelection` with options a/d/s/n
- [ ] Implement `saveSelected` to persist chosen books
- [ ] Add unit tests for parsing and categorization
- [ ] Test with real ISBN file against OpenLibrary
- [ ] Update README/help text with new command

---

## References

- **Similar Implementation:** `runImportCalibre` in `src/Libri/CLI/Commands.hs:332-350`
- **ISBN Fetch:** `fetchByISBN` in `src/Libri/ISBN/OpenLibrary.hs:79-105`
- **Duplicate Check:** `lookupByISBN` in `src/Libri/Storage/Index.hs:113-114`
- **OpenLibrary API:** https://openlibrary.org/dev/docs/api/books

---

## Notes

- User specifically requested verification step before saving - this is the key differentiator from existing import commands
- Command name `--import-isbn-txt` chosen by user (not default `--import-batch`)
- Full metadata display requested for review (not just title/author)
- Duplicates shown separately with option to selectively import
