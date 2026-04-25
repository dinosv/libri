# Data Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `libri --enrich` CLI command that batch-fills missing tags and descriptions from OpenLibrary by ISBN.

**Architecture:** One new module `Libri.CLI.Enrich` with pure merge logic and an IO runner. Wired into `Commands.hs` as a new `CmdEnrich` variant. Reuses the existing `fetchByISBNWith` and shared HTTP manager.

**Tech Stack:** Haskell, http-client (existing), OpenLibrary API (existing integration), hspec (testing)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `src/Libri/CLI/Enrich.hs` | Create | `needsEnrichment`, `mergeTags`, `enrichBook`, `runEnrich`, `EnrichResult` |
| `src/Libri/CLI/Commands.hs` | Modify | Add `CmdEnrich`, `--enrich` flag, dispatch to `runEnrich` |
| `libri.cabal` | Modify | Add `Libri.CLI.Enrich` to exposed-modules, `EnrichSpec` to test other-modules |
| `test/EnrichSpec.hs` | Create | Tests for `needsEnrichment`, `mergeTags` |
| `test/Main.hs` | Modify | Register `EnrichSpec` |

---

### Task 1: Create Enrich module with pure logic and tests

**Files:**
- Create: `src/Libri/CLI/Enrich.hs`
- Create: `test/EnrichSpec.hs`
- Modify: `libri.cabal`
- Modify: `test/Main.hs`

- [ ] **Step 1: Register modules in cabal**

In `libri.cabal`, add `Libri.CLI.Enrich` to the library `exposed-modules` (after `Libri.CLI.BatchImport`).

Add `EnrichSpec` to the test-suite `other-modules`.

- [ ] **Step 2: Write the failing tests**

Create `test/EnrichSpec.hs`:

```haskell
module EnrichSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Libri.CLI.Enrich (needsEnrichment, mergeTags, EnrichResult(..))
import Libri.Types (Book(..))
import Test.Hspec

mkBook :: Text -> Maybe Text -> [Text] -> Maybe Text -> Book
mkBook bookTitle bookIsbn bookTags bookComments =
  let ts = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = "1"
       , _isbn = bookIsbn
       , _title = bookTitle
       , _authors = ["Author"]
       , _series = Nothing
       , _seriesIndex = Nothing
       , _publisher = Nothing
       , _published = Nothing
       , _tags = bookTags
       , _rating = Nothing
       , _comments = bookComments
       , _location = Nothing
       , _custom = Map.empty
       , _added = ts
       , _modified = ts
       }

spec :: Spec
spec = describe "Enrich" $ do

  describe "needsEnrichment" $ do
    it "returns True for book with no tags and no comments" $
      needsEnrichment (mkBook "Test" (Just "123") [] Nothing) `shouldBe` True

    it "returns True for book with tags but no comments" $
      needsEnrichment (mkBook "Test" (Just "123") ["Fiction"] Nothing) `shouldBe` True

    it "returns True for book with comments but no tags" $
      needsEnrichment (mkBook "Test" (Just "123") [] (Just "A description")) `shouldBe` True

    it "returns False for book with both tags and comments" $
      needsEnrichment (mkBook "Test" (Just "123") ["Fiction"] (Just "A description")) `shouldBe` False

    it "returns False for book without ISBN" $
      needsEnrichment (mkBook "Test" Nothing [] Nothing) `shouldBe` False

  describe "mergeTags" $ do
    it "adds new tags to empty list" $
      mergeTags [] ["Fiction", "History"] `shouldBe` ["Fiction", "History"]

    it "deduplicates case-insensitively" $
      mergeTags ["fiction"] ["Fiction", "History"] `shouldBe` ["fiction", "History"]

    it "deduplicates accent-insensitively" $
      mergeTags ["Filosofía"] ["Filosofia", "History"] `shouldBe` ["Filosofía", "History"]

    it "caps new tags at 10" $
      let newTags = map (\n -> "Tag" <> (if n < 10 then "0" else "") <> show n)
                        ([1..15] :: [Int])
      in length (mergeTags [] newTags) `shouldBe` 10

    it "preserves existing tags and adds up to 10 new" $
      let existing = ["A", "B"]
          newTags = map (\n -> "Tag" <> show n) ([1..15] :: [Int])
      in length (mergeTags existing newTags) `shouldBe` 12

    it "returns existing when no new tags" $
      mergeTags ["Fiction"] [] `shouldBe` ["Fiction"]
```

- [ ] **Step 3: Register test in Main.hs**

Add to `test/Main.hs`:

```haskell
import qualified EnrichSpec
```

And in the `hspec` block:

```haskell
  EnrichSpec.spec
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cabal test 2>&1 | tail -5`
Expected: compilation error -- `Libri.CLI.Enrich` not found

- [ ] **Step 5: Write the implementation**

Create `src/Libri/CLI/Enrich.hs`:

```haskell
module Libri.CLI.Enrich
  ( EnrichResult (..)
  , needsEnrichment
  , mergeTags
  , enrichBook
  , runEnrich
  ) where

import Control.Concurrent (threadDelay)
import Control.Monad (forM, when)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Lens.Micro ((^.), (&), (.~))
import Libri.ISBN.OpenLibrary (fetchByISBNWith, newISBNManager)
import Libri.Storage.Yaml (loadBooks, saveBook)
import Libri.Text.Normalize (normalizeText)
import Libri.Types
import Network.HTTP.Client (Manager)
import System.IO (hFlush, stdout, hPutStrLn, stderr)
import System.Exit (exitFailure)

data EnrichResult
  = Enriched Int Bool
  | NotFound
  | AlreadyComplete
  | NoISBN
  deriving (Show, Eq)

needsEnrichment :: Book -> Bool
needsEnrichment book =
  case book ^. isbn of
    Nothing -> False
    Just _  -> null (book ^. tags) || book ^. comments == Nothing

mergeTags :: [Text] -> [Text] -> [Text]
mergeTags existing new =
  let existingNorm = map normalizeText existing
      isNew t = normalizeText t `notElem` existingNorm
      added = take 10 $ filter isNew new
  in existing ++ added

enrichBook :: Manager -> Book -> IO (Book, EnrichResult)
enrichBook mgr book =
  case book ^. isbn of
    Nothing -> pure (book, NoISBN)
    Just isbnVal -> do
      result <- fetchByISBNWith mgr isbnVal
      case result of
        Left (ISBNNotFound _) -> pure (book, NotFound)
        Left _ -> pure (book, NotFound)
        Right fetched ->
          let newTags = mergeTags (book ^. tags) (fetched ^. tags)
              tagsAdded = length newTags - length (book ^. tags)
              addedDesc = book ^. comments == Nothing && fetched ^. comments /= Nothing
              newComments = case book ^. comments of
                Just c  -> Just c
                Nothing -> fetched ^. comments
              enriched = book & tags .~ newTags
                              & comments .~ newComments
          in pure (enriched, Enriched tagsAdded addedDesc)

runEnrich :: Config -> IO ()
runEnrich cfg = do
  booksResult <- loadBooks cfg
  case booksResult of
    Left err -> do
      hPutStrLn stderr $ "Error loading books: " <> show err
      exitFailure
    Right bks -> do
      let toEnrich = filter needsEnrichment bks
          total = length toEnrich
      if total == 0
        then TIO.putStrLn "All books already have tags and descriptions."
        else do
          TIO.putStrLn $ "Enriching " <> tshow total <> " books with missing data...\n"
          mgr <- newISBNManager
          results <- forM (zip [1 :: Int ..] toEnrich) $ \(n, book) -> do
            TIO.putStr $ "  " <> tshow n <> "/" <> tshow total
                      <> ": " <> (book ^. title)
                      <> case book ^. isbn of
                           Just i  -> " (" <> i <> ")"
                           Nothing -> ""
                      <> "... "
            hFlush stdout
            (enriched, res) <- enrichBook mgr book
            printResult res
            case res of
              Enriched _ _ -> do
                saveResult <- saveBook cfg enriched
                case saveResult of
                  Left err -> TIO.putStrLn $ "    save error: " <> T.pack (show err)
                  Right () -> pure ()
              _ -> pure ()
            threadDelay 1000000
            pure res

          let updated = length [() | Enriched _ _ <- results]
              notFound = length [() | NotFound <- results]
          TIO.putStrLn ""
          TIO.putStrLn "Enrichment complete!"
          TIO.putStrLn $ "  " <> tshow updated <> " books updated"
          when (notFound > 0) $
            TIO.putStrLn $ "  " <> tshow notFound <> " books not found on OpenLibrary"
  where
    tshow :: Show a => a -> Text
    tshow = T.pack . show

printResult :: EnrichResult -> IO ()
printResult (Enriched tagCount hasDesc) = do
  let parts = (if tagCount > 0 then ["+" <> T.pack (show tagCount) <> " tags"] else [])
           ++ (if hasDesc then ["+description"] else [])
  case parts of
    [] -> TIO.putStrLn "no new data"
    _  -> TIO.putStrLn $ T.intercalate ", " parts
printResult NotFound = TIO.putStrLn "not found"
printResult AlreadyComplete = TIO.putStrLn "already complete"
printResult NoISBN = TIO.putStrLn "no ISBN"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cabal test 2>&1 | tail -30`
Expected: all tests PASS including new EnrichSpec

- [ ] **Step 7: Commit**

```bash
git add src/Libri/CLI/Enrich.hs test/EnrichSpec.hs test/Main.hs libri.cabal
git commit -m "feat: add Libri.CLI.Enrich with tag merging and batch enrichment"
```

---

### Task 2: Wire --enrich into Commands.hs

**Files:**
- Modify: `src/Libri/CLI/Commands.hs`

- [ ] **Step 1: Add CmdEnrich to the Command type**

Add after `CmdVersion`:

```haskell
  | CmdEnrich                        -- ^ Enrich books from OpenLibrary
```

- [ ] **Step 2: Add the --enrich flag parser**

Add `enrichCommand` after `versionCommand`:

```haskell
enrichCommand :: Parser Command
enrichCommand = flag' CmdEnrich
  ( long "enrich"
 <> help "Enrich books with missing tags/descriptions from OpenLibrary"
  )
```

Add `enrichCommand` to the `commandParser` alternatives (after `versionCommand`):

```haskell
  <|> enrichCommand
```

- [ ] **Step 3: Add the import and dispatch**

Add import at top:

```haskell
import Libri.CLI.Enrich (runEnrich)
```

Add case to `runCommand`:

```haskell
  CmdEnrich -> runEnrich cfg
```

- [ ] **Step 4: Verify it builds**

Run: `cabal build 2>&1 | tail -5`
Expected: builds with no errors

Run: `cabal test 2>&1 | tail -5`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/Libri/CLI/Commands.hs
git commit -m "feat: wire --enrich CLI flag to enrichment runner"
```

---

### Task 3: Smoke test

**Files:** None (testing only)

- [ ] **Step 1: Verify --help shows the new flag**

Run: `cabal run libri -- --help 2>&1 | grep enrich`
Expected: shows `--enrich` with help text

- [ ] **Step 2: Run enrichment on the actual library**

Run: `cabal run libri -- --enrich 2>&1 | tail -20`

Verify:
- Progress lines appear per book
- Tags and descriptions are being added
- Summary at the end shows updated count

- [ ] **Step 3: Check enriched data**

Run: check a few books that were previously missing tags:

```bash
grep -E "^tags:" data/books/4.yaml
grep -E "^comments:" data/books/4.yaml
```

Verify tags and/or comments were filled in.

- [ ] **Step 4: Commit any fixes if needed**

```bash
git add -A && git commit -m "fix: smoke test corrections"
```
