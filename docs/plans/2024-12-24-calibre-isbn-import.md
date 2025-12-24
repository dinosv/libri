# Calibre ISBN Import Fix - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Import ISBN and other identifiers from Calibre's `identifiers` table during library migration.

**Architecture:** Add `getIdentifiers` query to CalibreImport, extract ISBN (prefer ISBN-13), prefix other identifiers with `identifier:` for custom fields. Add merge logic to Yaml.hs to preserve libri-owned fields on re-import.

**Tech Stack:** Haskell, sqlite-simple, HSpec for testing

---

## Task 1: Add CalibreImportSpec Test File

**Files:**
- Create: `test/CalibreImportSpec.hs`
- Modify: `test/Main.hs:4-12`
- Modify: `libri.cabal:101` (add CalibreImportSpec to other-modules)

**Step 1: Create the test file with failing tests for getIdentifiers**

Create `test/CalibreImportSpec.hs`:

```haskell
module CalibreImportSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Libri.Storage.CalibreImport (extractIsbn, partitionIdentifiers)
import Test.Hspec

spec :: Spec
spec = describe "Calibre Import" $ do

  describe "extractIsbn" $ do
    it "returns Nothing for empty list" $ do
      extractIsbn [] `shouldBe` Nothing

    it "prefers ISBN-13 over ISBN-10" $ do
      extractIsbn [("isbn", "0134685991"), ("isbn", "9780134685991")]
        `shouldBe` Just "9780134685991"

    it "returns ISBN-13 when only ISBN-13 present" $ do
      extractIsbn [("isbn", "9780134685991")]
        `shouldBe` Just "9780134685991"

    it "returns ISBN-10 when only ISBN-10 present" $ do
      extractIsbn [("isbn", "0134685991")]
        `shouldBe` Just "0134685991"

    it "ignores non-isbn identifiers" $ do
      extractIsbn [("amazon", "B07N1XLQ7D"), ("google", "abc123")]
        `shouldBe` Nothing

  describe "partitionIdentifiers" $ do
    it "separates isbn from other identifiers" $ do
      let ids = [("isbn", "9780134685991"), ("amazon", "B07N1XLQ7D")]
          (maybeIsbn, others) = partitionIdentifiers ids
      maybeIsbn `shouldBe` Just "9780134685991"
      others `shouldBe` Map.fromList [("identifier:amazon", "B07N1XLQ7D")]

    it "prefixes all non-isbn identifiers with identifier:" $ do
      let ids = [("amazon", "B07N1XLQ7D"), ("google", "abc123"), ("goodreads", "12345")]
          (_, others) = partitionIdentifiers ids
      Map.keys others `shouldMatchList`
        ["identifier:amazon", "identifier:google", "identifier:goodreads"]

    it "handles empty identifier list" $ do
      let (maybeIsbn, others) = partitionIdentifiers []
      maybeIsbn `shouldBe` Nothing
      others `shouldBe` Map.empty

    it "handles multiple isbn entries by preferring ISBN-13" $ do
      let ids = [("isbn", "0134685991"), ("isbn", "9780134685991"), ("amazon", "B07N")]
          (maybeIsbn, others) = partitionIdentifiers ids
      maybeIsbn `shouldBe` Just "9780134685991"
      Map.lookup "identifier:amazon" others `shouldBe` Just "B07N"
```

**Step 2: Add CalibreImportSpec to test/Main.hs**

Modify `test/Main.hs` to import and run the new spec:

```haskell
module Main (main) where

import Test.Hspec
import qualified TypesSpec
import qualified SearchSpec
import qualified BatchImportSpec
import qualified CalibreImportSpec

main :: IO ()
main = hspec $ do
  TypesSpec.spec
  SearchSpec.spec
  BatchImportSpec.spec
  CalibreImportSpec.spec
```

**Step 3: Add CalibreImportSpec to libri.cabal**

In `libri.cabal`, update the `other-modules` under `test-suite libri-test`:

```cabal
    other-modules:    TypesSpec
                    , SearchSpec
                    , BatchImportSpec
                    , CalibreImportSpec
```

**Step 4: Run tests to verify they fail**

Run: `cabal test`

Expected: Compilation error - `extractIsbn` and `partitionIdentifiers` not exported from CalibreImport

**Step 5: Commit**

```bash
git add test/CalibreImportSpec.hs test/Main.hs libri.cabal
git commit -m "$(cat <<'EOF'
test: add failing tests for Calibre identifier extraction

Tests for extractIsbn and partitionIdentifiers functions that will
handle ISBN extraction from Calibre's identifiers table.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Implement extractIsbn and partitionIdentifiers

**Files:**
- Modify: `src/Libri/Storage/CalibreImport.hs:1-4` (exports)
- Modify: `src/Libri/Storage/CalibreImport.hs:168-220` (add new functions after parseDate)

**Step 1: Export the new functions**

Update the module header in `src/Libri/Storage/CalibreImport.hs`:

```haskell
module Libri.Storage.CalibreImport
  ( importFromCalibre
  , CalibreBook (..)
  , extractIsbn
  , partitionIdentifiers
  ) where
```

**Step 2: Add the implementation after parseDate function (around line 216)**

Add at the end of the file:

```haskell
-- | Extract ISBN from a list of identifiers, preferring ISBN-13
extractIsbn :: [(Text, Text)] -> Maybe Text
extractIsbn ids =
  let isbns = [val | (typ, val) <- ids, typ == "isbn"]
      isbn13s = filter (\v -> T.length v == 13) isbns
      isbn10s = filter (\v -> T.length v == 10) isbns
   in case isbn13s of
        (x : _) -> Just x
        [] -> case isbn10s of
          (x : _) -> Just x
          [] -> Nothing

-- | Partition identifiers into ISBN and other identifiers
-- Returns (Maybe ISBN, Map of prefixed identifiers)
partitionIdentifiers :: [(Text, Text)] -> (Maybe Text, Map.Map Text Text)
partitionIdentifiers ids =
  let maybeIsbn = extractIsbn ids
      others = [(T.pack "identifier:" <> typ, val) | (typ, val) <- ids, typ /= "isbn"]
   in (maybeIsbn, Map.fromList others)
```

**Step 3: Run tests to verify they pass**

Run: `cabal test`

Expected: All CalibreImportSpec tests pass

**Step 4: Commit**

```bash
git add src/Libri/Storage/CalibreImport.hs
git commit -m "$(cat <<'EOF'
feat: add extractIsbn and partitionIdentifiers functions

- extractIsbn: prefers ISBN-13, falls back to ISBN-10
- partitionIdentifiers: separates ISBN from other identifiers,
  prefixes non-ISBN identifiers with "identifier:"

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add getIdentifiers Database Query

**Files:**
- Modify: `src/Libri/Storage/CalibreImport.hs:86-95` (add after getAuthors)

**Step 1: Add getIdentifiers function after getAuthors (around line 95)**

Insert after the `getAuthors` function:

```haskell
-- | Get identifiers for a book (ISBN, Amazon, Google, etc.)
getIdentifiers :: Connection -> Int -> IO [(Text, Text)]
getIdentifiers conn bookId = do
  result <- try $ query conn
    "SELECT type, val FROM identifiers WHERE book = ?"
    (Only bookId) :: IO (Either SomeException [(Text, Text)])
  case result of
    Left _ -> pure []  -- Table might not exist in old Calibre versions
    Right rows -> pure rows
```

**Step 2: Run tests to verify nothing broke**

Run: `cabal test`

Expected: All tests still pass

**Step 3: Commit**

```bash
git add src/Libri/Storage/CalibreImport.hs
git commit -m "$(cat <<'EOF'
feat: add getIdentifiers query for Calibre identifiers table

Queries the identifiers table for ISBN, Amazon ASIN, Google Books ID,
and other identifiers. Gracefully handles missing table in old Calibre
versions.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Wire Up Identifiers in importBooks and convertBook

**Files:**
- Modify: `src/Libri/Storage/CalibreImport.hs:72-85` (importBooks - add getIdentifiers call)
- Modify: `src/Libri/Storage/CalibreImport.hs:169-203` (convertBook - use identifiers)

**Step 1: Update importBooks to fetch identifiers**

In `importBooks`, add `getIdentifiers` call (around line 80):

```haskell
-- | Import all books from the database
importBooks :: FilePath -> IO [Book]
importBooks dbPath = do
  conn <- open dbPath

  -- Get all books
  calibreBooks <- query_ conn
    "SELECT id, title, sort, timestamp, pubdate, series_index, path, has_cover, last_modified \
    \FROM books" :: IO [CalibreBook]

  -- Convert each book
  books <- forM calibreBooks $ \cb -> do
    authors <- getAuthors conn (cbId cb)
    identifiers <- getIdentifiers conn (cbId cb)
    tags <- getTags conn (cbId cb)
    series <- getSeries conn (cbId cb)
    publisher <- getPublisher conn (cbId cb)
    rating <- getRating conn (cbId cb)
    comments <- getComments conn (cbId cb)
    customCols <- getCustomColumns conn (cbId cb)

    convertBook cb authors identifiers tags series publisher rating comments customCols

  close conn
  pure books
```

**Step 2: Update convertBook signature and implementation**

Update `convertBook` to accept and use identifiers:

```haskell
-- | Convert a Calibre book to our Book type
convertBook
  :: CalibreBook
  -> [Text]           -- authors
  -> [(Text, Text)]   -- identifiers (NEW)
  -> [Text]           -- tags
  -> Maybe Text       -- series
  -> Maybe Text       -- publisher
  -> Maybe Int        -- rating
  -> Maybe Text       -- comments
  -> Map.Map Text Value
  -> IO Book
convertBook cb authors identifiers tags series publisher rating comments customCols = do
  now <- getCurrentTime

  -- Try to parse the publication date
  let pubDate = cbPubdate cb >>= parseDate

  -- Extract ISBN and other identifiers
  let (maybeIsbn, otherIds) = partitionIdentifiers identifiers
      -- Merge other identifiers into custom, converting Text to Value
      customWithIds = Map.union
        (Map.map (String) otherIds)
        (Map.delete "location" customCols)

  pure
    Book
      { _bookId = T.pack $ show (cbId cb)
      , _isbn = maybeIsbn
      , _title = cbTitle cb
      , _authors = authors
      , _series = series
      , _seriesIndex = cbSeriesIndex cb
      , _publisher = publisher
      , _published = pubDate
      , _tags = tags
      , _rating = rating
      , _comments = comments
      , _location = Map.lookup "location" customCols >>= valueToText
      , _custom = customWithIds
      , _added = fromMaybe now (cbTimestamp cb)
      , _modified = cbLastModified cb
      }
```

**Step 3: Run tests**

Run: `cabal test`

Expected: All tests pass

**Step 4: Commit**

```bash
git add src/Libri/Storage/CalibreImport.hs
git commit -m "$(cat <<'EOF'
feat: wire up identifier extraction in Calibre import

- importBooks now calls getIdentifiers for each book
- convertBook extracts ISBN and adds prefixed identifiers to custom
- ISBN field is now populated from Calibre's identifiers table

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add Merge Logic Tests

**Files:**
- Create: `test/YamlSpec.hs`
- Modify: `test/Main.hs` (add YamlSpec)
- Modify: `libri.cabal` (add YamlSpec to other-modules)

**Step 1: Create test file for merge logic**

Create `test/YamlSpec.hs`:

```haskell
module YamlSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Aeson (Value(..))
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Libri.Storage.Yaml (mergeBooks)
import Libri.Types (Book(..))
import Test.Hspec

spec :: Spec
spec = describe "YAML Storage" $ do

  describe "mergeBooks" $ do
    let testTime1 = UTCTime (fromGregorian 2025 1 1) 0
        testTime2 = UTCTime (fromGregorian 2025 1 2) 0
        calibreBook = Book
          { _bookId = "42"
          , _isbn = Just "9780134685991"
          , _title = "Updated Title"
          , _authors = ["New Author"]
          , _series = Just "Series"
          , _seriesIndex = Just 1.0
          , _publisher = Just "Publisher"
          , _published = Nothing
          , _tags = ["tag1", "tag2"]
          , _rating = Just 4
          , _comments = Just "New comment"
          , _location = Nothing  -- Calibre doesn't know location
          , _custom = Map.fromList [("identifier:amazon", String "ASIN123")]
          , _added = testTime2
          , _modified = testTime2
          }
        existingBook = Book
          { _bookId = "42"
          , _isbn = Nothing  -- Was missing
          , _title = "Old Title"
          , _authors = ["Old Author"]
          , _series = Nothing
          , _seriesIndex = Nothing
          , _publisher = Nothing
          , _published = Nothing
          , _tags = []
          , _rating = Nothing
          , _comments = Nothing
          , _location = Just "Shelf A"  -- User set this
          , _custom = Map.fromList [("myfield", String "myvalue")]
          , _added = testTime1  -- Original add time
          , _modified = testTime1
          }

    it "preserves existing location" $ do
      let merged = mergeBooks calibreBook existingBook
      _location merged `shouldBe` Just "Shelf A"

    it "preserves existing added timestamp" $ do
      let merged = mergeBooks calibreBook existingBook
      _added merged `shouldBe` testTime1

    it "uses calibre data for title, authors, etc." $ do
      let merged = mergeBooks calibreBook existingBook
      _title merged `shouldBe` "Updated Title"
      _authors merged `shouldBe` ["New Author"]
      _isbn merged `shouldBe` Just "9780134685991"

    it "preserves non-identifier custom fields" $ do
      let merged = mergeBooks calibreBook existingBook
      Map.lookup "myfield" (_custom merged) `shouldBe` Just (String "myvalue")

    it "adds new identifier custom fields from calibre" $ do
      let merged = mergeBooks calibreBook existingBook
      Map.lookup "identifier:amazon" (_custom merged) `shouldBe` Just (String "ASIN123")

    it "keeps bookId from existing book" $ do
      let merged = mergeBooks calibreBook existingBook
      _bookId merged `shouldBe` "42"
```

**Step 2: Add YamlSpec to Main.hs**

```haskell
module Main (main) where

import Test.Hspec
import qualified TypesSpec
import qualified SearchSpec
import qualified BatchImportSpec
import qualified CalibreImportSpec
import qualified YamlSpec

main :: IO ()
main = hspec $ do
  TypesSpec.spec
  SearchSpec.spec
  BatchImportSpec.spec
  CalibreImportSpec.spec
  YamlSpec.spec
```

**Step 3: Add YamlSpec to libri.cabal**

```cabal
    other-modules:    TypesSpec
                    , SearchSpec
                    , BatchImportSpec
                    , CalibreImportSpec
                    , YamlSpec
```

**Step 4: Run tests to verify they fail**

Run: `cabal test`

Expected: Compilation error - `mergeBooks` not exported

**Step 5: Commit**

```bash
git add test/YamlSpec.hs test/Main.hs libri.cabal
git commit -m "$(cat <<'EOF'
test: add failing tests for book merge logic

Tests for mergeBooks function that combines Calibre data with existing
libri data, preserving location and non-identifier custom fields.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Implement mergeBooks Function

**Files:**
- Modify: `src/Libri/Storage/Yaml.hs:1-16` (add export)
- Modify: `src/Libri/Storage/Yaml.hs:38` (add Data.Aeson import)
- Modify: `src/Libri/Storage/Yaml.hs` (add mergeBooks function after saveBook)

**Step 1: Add mergeBooks to exports**

```haskell
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
    -- * Merging
  , mergeBooks
    -- * Directory Management
  , initDataDir
  , getDataDir
  , expandPath
  ) where
```

**Step 2: Add Data.Aeson import**

After line 26, add:

```haskell
import Data.Aeson (Value(..))
```

**Step 3: Add mergeBooks function after saveBook (around line 119)**

```haskell
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
        { _location = _location existing
        , _added = _added existing
        , _custom = mergedCustom
        }
```

**Step 4: Run tests**

Run: `cabal test`

Expected: All YamlSpec tests pass

**Step 5: Commit**

```bash
git add src/Libri/Storage/Yaml.hs
git commit -m "$(cat <<'EOF'
feat: add mergeBooks function for re-import support

Merges Calibre import data with existing libri book, preserving:
- location (user-set shelf location)
- added timestamp (original import time)
- non-identifier custom fields (user additions)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Wire Up Merge in Import Flow

**Files:**
- Modify: `src/Libri/Storage/CalibreImport.hs:1-4` (add saveImportedBooks export)
- Modify: `src/Libri/Storage/CalibreImport.hs:17-19` (add Yaml import)
- Modify: `src/Libri/Storage/CalibreImport.hs` (add saveImportedBooks function)

**Step 1: Add imports for Yaml functions**

After line 18 (`import Libri.Types`), add:

```haskell
import Libri.Storage.Yaml (loadBook, saveBook, mergeBooks, getDataDir)
```

**Step 2: Add saveImportedBooks to exports**

```haskell
module Libri.Storage.CalibreImport
  ( importFromCalibre
  , saveImportedBooks
  , CalibreBook (..)
  , extractIsbn
  , partitionIdentifiers
  ) where
```

**Step 3: Add saveImportedBooks function at end of file**

```haskell
-- | Save imported books, merging with existing if present
saveImportedBooks :: Config -> [Book] -> IO [Either LibriError ()]
saveImportedBooks cfg books = do
  dir <- getDataDir cfg
  let booksDir = dir </> "books"
  forM books $ \book -> do
    let filename = T.unpack (_bookId book) <> ".yaml"
        path = booksDir </> filename
    existingResult <- loadBook path
    let bookToSave = case existingResult of
          Right existing -> mergeBooks book existing
          Left _ -> book  -- No existing book, use as-is
    saveBook cfg bookToSave
```

**Step 4: Add FilePath import**

Ensure `System.FilePath ((</>))` is imported (should already be there from line 19).

**Step 5: Run tests**

Run: `cabal test`

Expected: All tests pass

**Step 6: Commit**

```bash
git add src/Libri/Storage/CalibreImport.hs
git commit -m "$(cat <<'EOF'
feat: add saveImportedBooks with merge support

Saves imported books, checking for existing files and merging
when found. This enables re-importing while preserving user data.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Update CLI to Use New Import Flow

**Files:**
- Modify: `src/Libri/CLI/Commands.hs` (update import handler to use saveImportedBooks)

**Step 1: Read Commands.hs to understand current structure**

First examine the current implementation to find where to modify.

**Step 2: Update the import command handler**

Locate the calibre import handler and update it to:
1. Call `importFromCalibre`
2. Call `saveImportedBooks` instead of individual saves
3. Report results

The exact change depends on the current structure - adjust as needed.

**Step 3: Build and manually test**

Run: `cabal build`
Run: `cabal run libri -- --import-calibre /path/to/test/calibre/library`

Expected: Books import with ISBN populated

**Step 4: Commit**

```bash
git add src/Libri/CLI/Commands.hs
git commit -m "$(cat <<'EOF'
feat: update CLI import to use merge-aware save

The --import-calibre command now uses saveImportedBooks which
merges with existing books, preserving location and custom fields.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Final Integration Test

**Step 1: Run full test suite**

Run: `cabal test`

Expected: All tests pass

**Step 2: Build release**

Run: `cabal build`

Expected: Clean build with no warnings

**Step 3: Test with real Calibre library (if available)**

Run: `cabal run libri -- --import-calibre ~/path/to/calibre/library`

Check a resulting YAML file in `~/.local/share/libri/books/` to verify ISBN is present.

**Step 4: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: final cleanup for Calibre ISBN import feature

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

| Task | Description | Est. Lines |
|------|-------------|------------|
| 1 | Add CalibreImportSpec tests | ~60 |
| 2 | Implement extractIsbn, partitionIdentifiers | ~20 |
| 3 | Add getIdentifiers query | ~10 |
| 4 | Wire up in importBooks/convertBook | ~30 |
| 5 | Add YamlSpec merge tests | ~70 |
| 6 | Implement mergeBooks | ~15 |
| 7 | Add saveImportedBooks | ~15 |
| 8 | Update CLI handler | ~10 |
| 9 | Integration test | ~0 |

**Total:** ~230 lines of new/modified code across 9 commits
