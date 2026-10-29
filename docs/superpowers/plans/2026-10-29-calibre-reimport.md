# Safe Calibre Re-import Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Goal: make `libri --import-calibre PATH` add new Calibre books freely while never changing an existing libri book unless Calibre changed it since the last import and the user chose to take the change.

Architecture: a sync-state file (`<dataDir>/calibre-sync.yaml`) records, per Calibre library, which Calibre book maps to which libri book plus per-field fingerprints of what was last imported. Pure modules do fingerprinting, matching and conflict resolution; a thin IO driver asks questions through an injected `Ask` function so whole runs are testable with scripted answers. The SQLite reader (`Libri.Storage.CalibreImport`) keeps reading Calibre; the old merge path (`mergeBooks`, `findExistingBook`, `saveImportedBooks`) is removed.

Tech stack: Haskell (GHC 9.10, GHC2021, OverloadedStrings), hspec, sqlite-simple, yaml/aeson, bytestring. No new dependencies.

Spec: `docs/superpowers/specs/2026-10-29-calibre-reimport-design.md`

## Global Constraints

- Never write to the real `data/` directory in tests or verification; use temp dirs (`withSystemTempDirectory`) or a scratch copy.
- Fields libri owns are never changed by an import: id, location, added, and custom keys that are not `identifier:*`.
- Taking Calibre's identifiers adds/updates `identifier:*` keys; it never removes a libri identifier.
- A Calibre library is identified by its library UUID; an unreadable UUID is a hard error.
- Every question has a non-destructive answer on EOF: conflicts keep libri, ISBN guesses add nothing, baseline books stay undecided (asked again), home question stays unanswered.
- Exit status non-zero when any question was unanswered or any save failed.
- Prose in prompts and docs: British English.
- Match surrounding code style: explicit export lists, Haddock `-- |` comments, pure core plus thin IO runner, `Either LibriError` for failures.

## Review Focus

1. A libri book file that fails to parse: the import must abort before writing anything (otherwise the hidden book gets re-added as a duplicate). Test in Task 6.
2. Calibre returning the same tags or identifiers in a different order: must not count as a change or a conflict. Test in Task 2.
3. Two Calibre entries with the same ISBN in one import (the double-scan case): the second must not merge into the book just added for the first. Test in Task 4.
4. EOF in the middle of a field-by-field choice: fields not yet decided keep libri's value and the run counts it as unanswered. Test in Task 6.
5. A corrupt `calibre-sync.yaml`: abort with an error and leave the file untouched; never treat it as empty. Test in Task 3.

## File Structure

- Modify `src/Libri/Storage/CalibreImport.hs`: SQLite reading only. Returns a `CalibreLibrary`; parsing fixes; drop matching/merging code.
- Create `src/Libri/Storage/CalibreSync.hs`: `CalibreField`, canonical field text, FNV-1a fingerprints, sync-state types, YAML load/save.
- Create `src/Libri/Storage/CalibreReconcile.hs`: pure matching (rules 1-5) and conflict computation/application.
- Create `src/Libri/CLI/CalibreImport.hs`: the interactive driver and summary.
- Modify `src/Libri/CLI/Commands.hs`: `CmdImportCalibre` calls the driver; remove old runner.
- Modify `src/Libri/Storage/Yaml.hs`: remove `mergeBooks`.
- Tests: `test/CalibreImportSpec.hs` (rewrite), `test/CalibreSyncSpec.hs`, `test/CalibreReconcileSpec.hs`, `test/CalibreImportDriverSpec.hs`; register in `libri.cabal` and `test/Main.hs`. Remove the `mergeBooks` block from `test/YamlSpec.hs`.

---

### Task 1: Calibre reader fixes

Files:
- Modify: `src/Libri/Storage/CalibreImport.hs`
- Test: `test/CalibreImportSpec.hs`

Interfaces:
- Produces:
  - `data CalibreLibrary = CalibreLibrary { clUuid :: Text, clPath :: FilePath, clBooks :: [Book] } deriving (Show)`
  - `importFromCalibre :: FilePath -> IO (Either LibriError CalibreLibrary)` (Left `CalibreImportError "Calibre library has no library UUID"` when `library_id` is empty or unreadable)
  - `parseDate :: Text -> Maybe Day` (now exported)
  - `extractIsbn`, `partitionIdentifiers`, `calibreIdentifier` unchanged in signature
  - Every book from `importFromCalibre` has `identifier:calibre` = `calibreIdentifier clUuid calibreId` (already true).

- [ ] Step 1: Write failing tests in `test/CalibreImportSpec.hs`. Delete the `findExistingBook` block and its import; add:

```haskell
it "normalises hyphens and spaces before choosing an ISBN" $
  extractIsbn [("isbn", "978-84-376-0494-7")] `shouldBe` Just "9788437604947"
it "upper-cases an ISBN-10 check digit" $
  extractIsbn [("isbn", "0-8044-2957-x")] `shouldBe` Just "080442957X"
it "treats Calibre's 0101-01-01 sentinel as no date" $
  parseDate "0101-01-01 00:00:00+00:00" `shouldBe` Nothing
it "still parses a real Calibre date" $
  parseDate "2007-01-01 00:00:00+00:00" `shouldBe` Just (fromGregorian 2007 1 1)
```

Add one IO test using a temp SQLite file (create with `sqlite-simple` `execute_`): a `metadata.db` whose `library_id` table is empty → `importFromCalibre dir` returns `Left (CalibreImportError _)`. The test may create only the tables `importBooks` queries; add `sqlite-simple` to the test-suite `build-depends`.

- [ ] Step 2: Run `cabal test 2>&1 | tail -30`. Expected: compile failure (`parseDate` not exported) or the new examples fail.

- [ ] Step 3: Implement. `extractIsbn` applies `T.toUpper . T.filter (\c -> not (isSpace c) && c /= '-')` before the 10/13 length check. `parseDate` returns Nothing when the parsed year is below 1000; apply the same rule to `cbTimestamp` in `convertBook` (fall back to `now`). `getLibraryUuid` returns `Maybe Text` (Nothing for empty/unreadable) and `importFromCalibre` maps Nothing to the Left above. `getTags` gains `ORDER BY t.name`. Remove `findExistingBook`, `saveImportedBooks` and their imports/exports; `Commands.hs` keeps compiling by temporarily adapting `runImportCalibre` to `clBooks` and `saveBook` (Task 7 replaces it).

- [ ] Step 4: Run `cabal test 2>&1 | tail -5`. Expected: `0 failures`.

- [ ] Step 5: Commit: `git commit -m "fix: Calibre reader normalises ISBNs, drops sentinel dates, requires library UUID"`

### Task 2: Field fingerprints

Files:
- Create: `src/Libri/Storage/CalibreSync.hs` (fingerprint part)
- Test: `test/CalibreSyncSpec.hs`

Interfaces:
- Produces:
  - `data CalibreField = FTitle | FAuthors | FSeries | FSeriesIndex | FPublisher | FPublished | FIsbn | FTags | FRating | FComments | FIdentifiers deriving (Show, Eq, Ord, Enum, Bounded)`
  - `fieldKey :: CalibreField -> Text` → `"title" "authors" "series" "seriesIndex" "publisher" "published" "isbn" "tags" "rating" "comments" "identifiers"`
  - `fieldCanonical :: CalibreField -> Book -> Text`
  - `type FieldPrints = Map CalibreField Text`
  - `fieldPrints :: Book -> FieldPrints` (all 11 fields)
  - `fnv1a64Hex :: Text -> Text` (FNV-1a 64-bit over UTF-8 bytes, 16 lowercase hex digits)
  - `calibreIdentifiers :: Book -> Map Text Value` (custom keys starting `identifier:` except `identifier:calibre`)

Canonical text rules (they decide what counts as a change): `Maybe` values render as `"-"` for Nothing and `"+" <> value` for Just; lists join with `"\US"`; authors keep order; tags are sorted; identifiers render sorted `key=value` pairs joined with `"\US"` (non-string values via `show`); series index, rating and published use `show`.

- [ ] Step 1: Write failing tests:

```haskell
it "pins the FNV-1a test vectors" $ do
  fnv1a64Hex "" `shouldBe` "cbf29ce484222325"
  fnv1a64Hex "a" `shouldBe` "af63dc4c8601ec8c"
it "ignores tag order" $
  fieldPrints b { _tags = ["Arte", "Historia"] } Map.! FTags
    `shouldBe` fieldPrints b { _tags = ["Historia", "Arte"] } Map.! FTags
it "ignores identifier order and the calibre provenance key" $ ...  -- same identifiers in two maps built in different orders, one with an extra identifier:calibre → equal FIdentifiers print
it "distinguishes no publisher from an empty publisher" $
  fieldPrints b { _publisher = Nothing } Map.! FPublisher
    `shouldNotBe` fieldPrints b { _publisher = Just "" } Map.! FPublisher
it "keeps author order significant" $ ...  -- ["A","B"] vs ["B","A"] differ
```

- [ ] Step 2: Run `cabal test`. Expected: compile failure, module missing. (Register the module in `libri.cabal` exposed-modules and the spec in test-suite `other-modules` and `test/Main.hs` as part of this step.)

- [ ] Step 3: Implement in `CalibreSync.hs` (use `Data.ByteString.foldl'` over `encodeUtf8`; offset basis `0xcbf29ce484222325`, prime `0x100000001b3`, `Word64` arithmetic).

- [ ] Step 4: Run `cabal test 2>&1 | tail -5`. Expected: `0 failures`.

- [ ] Step 5: Commit: `git commit -m "feat: per-field fingerprints for Calibre records"`

### Task 3: Sync state file

Files:
- Modify: `src/Libri/Storage/CalibreSync.hs`
- Test: `test/CalibreSyncSpec.hs`

Interfaces:
- Consumes: `FieldPrints`, `fieldKey` (Task 2); `encodeFileAtomic`, `getDataDir` from `Libri.Storage.Yaml`.
- Produces:
  - `data HomeStatus = HomeYes | HomeNo | HomeUnanswered deriving (Show, Eq)`
  - `data SyncEntry = SyncMapped BookId FieldPrints | SyncIgnored | SyncPending deriving (Show, Eq)` (`SyncPending`: seen on a baseline run, left undecided; asked again next run)
  - `data LibrarySync = LibrarySync { lsPath :: FilePath, lsHome :: HomeStatus, lsBooks :: Map Text SyncEntry } deriving (Show, Eq)` (keys are namespaced refs `<uuid>:<id>`)
  - `newtype SyncState = SyncState { syncLibraries :: Map Text LibrarySync } deriving (Show, Eq)` (key: library UUID)
  - `emptySyncState :: SyncState`
  - `setHomeLibrary :: Text -> SyncState -> SyncState` (that library becomes `HomeYes`; any other `HomeYes` becomes `HomeNo`)
  - `syncFilePath :: Config -> IO FilePath` (`<dataDir>/calibre-sync.yaml`)
  - `loadSyncState :: Config -> IO (Either LibriError SyncState)` (missing file → `Right emptySyncState`; parse failure → `Left (ParseError path msg)`)
  - `saveSyncState :: Config -> SyncState -> IO (Either LibriError ())` (atomic)

YAML layout:

```yaml
libraries:
  e9116e96-1573-4409-965e-8e0ee617fcdf:
    path: /path/to/Calibre Library
    home: yes            # yes | no | unanswered
    books:
      "e9116e96-…:46":
        status: mapped   # mapped | ignored | pending
        book: <libri uuid>          # mapped only
        fields: {title: <hex>, …}   # mapped only, keyed by fieldKey
```

- [ ] Step 1: Write failing tests: round-trip of a state with one library containing one mapped, one ignored and one pending entry (`save` then `load` equals the original); missing file loads as `emptySyncState`; a file containing `libraries: [oops` returns `Left (ParseError …)` and its bytes are unchanged afterwards (Review Focus 5); `setHomeLibrary "B"` on a state where "A" is `HomeYes` leaves "A" `HomeNo` and "B" `HomeYes`.

- [ ] Step 2: Run `cabal test`. Expected: compile failure / new examples fail.

- [ ] Step 3: Implement with hand-written `ToJSON`/`FromJSON` instances matching the layout above (unknown field keys in `fields` are an error).

- [ ] Step 4: Run `cabal test 2>&1 | tail -5`. Expected: `0 failures`.

- [ ] Step 5: Commit: `git commit -m "feat: calibre-sync.yaml state file"`

### Task 4: Matching

Files:
- Create: `src/Libri/Storage/CalibreReconcile.hs` (matching part)
- Test: `test/CalibreReconcileSpec.hs`

Interfaces:
- Consumes: `LibrarySync`, `SyncEntry`, `HomeStatus` (Task 3).
- Produces:
  - `data Match = MatchMapped Book FieldPrints | MatchIgnored | MatchPending | MatchDeletedInLibri | MatchByRef Book | MatchBareRef Book | MatchIsbnGuess Book | NoMatch deriving (Show, Eq)`
    (`MatchMapped` carries the libri book and the stored prints)
  - `calibreRefOf :: Book -> Maybe Text` (the `identifier:calibre` string value)
  - `matchBook :: Bool -> Maybe LibrarySync -> [Book] -> Book -> Match`
    (first argument: whether the bare-id rule may be used, i.e. the library is the home library in this run; second: this library's sync entry, if any; third: current collection; fourth: incoming Calibre book)

Rules in order (spec section 2): (1) sync entry for the incoming ref → `MatchMapped` if the mapped id exists in the collection, else `MatchDeletedInLibri`; `SyncIgnored` → `MatchIgnored`; `SyncPending` → `MatchPending`. (2) a book whose `identifier:calibre` equals the namespaced ref → `MatchByRef`. (3) only when the first argument is True: a book whose `identifier:calibre` equals the bare numeric id (text after the last `:`) → `MatchBareRef`. (4) a book with no `identifier:calibre` key at all and an equal ISBN after `normalizeISBN` (from `Libri.CLI.BatchImport`; move it to `Libri.Storage.CalibreSync` or a shared place if the import cycle requires) → `MatchIsbnGuess`. (5) `NoMatch`.

- [ ] Step 1: Write failing tests, one per rule, plus:
  - priority: a collection holding both a namespaced-ref book and an ISBN-equal book returns `MatchByRef`, regardless of list order (test both orders);
  - bare id is ignored when the first argument is False (foreign or unanswered library);
  - the ISBN rule skips a book that carries any `identifier:calibre` (bare or namespaced);
  - Review Focus 3: after a `NoMatch` book is added to the collection (with its namespaced `identifier:calibre`), a second incoming book with the same ISBN but a different Calibre id returns `NoMatch`, not `MatchIsbnGuess`.

- [ ] Step 2: Run `cabal test`. Expected: compile failure / failing examples.

- [ ] Step 3: Implement `matchBook`.

- [ ] Step 4: Run `cabal test 2>&1 | tail -5`. Expected: `0 failures`.

- [ ] Step 5: Commit: `git commit -m "feat: prioritised Calibre book matching"`

### Task 5: Conflicts

Files:
- Modify: `src/Libri/Storage/CalibreReconcile.hs`
- Test: `test/CalibreReconcileSpec.hs`

Interfaces:
- Consumes: `CalibreField`, `FieldPrints`, `fieldPrints`, `fieldCanonical`, `calibreIdentifiers` (Task 2).
- Produces:
  - `changedFields :: FieldPrints -> FieldPrints -> [CalibreField]` (stored vs incoming; fields whose print differs, or is missing from stored)
  - `differingFields :: [CalibreField] -> Book -> Book -> [CalibreField]` (of the given fields, those whose canonical text differs between libri book and Calibre book)
  - `data FieldChoice = KeepLibri | TakeCalibre | UnionTags deriving (Show, Eq)`
  - `applyChoices :: [(CalibreField, FieldChoice)] -> Book -> Book -> Book` (choices, Calibre book, libri book → updated libri book)
  - `fieldDisplay :: CalibreField -> Book -> Text` (human-readable value for the side-by-side; comments truncated to 60 characters with "…")

- [ ] Step 1: Write failing tests:
  - only comments changed in Calibre → `changedFields` is `[FComments]`, so libri's curated tags never appear;
  - `differingFields [FComments, FTags] libri calibre` drops a field where libri already has Calibre's value;
  - `TakeCalibre` on `FTitle` copies the title and nothing else; id, location, added and a non-identifier custom key stay libri's;
  - `UnionTags` keeps libri's tags in order followed by Calibre-only tags, deduplicated with `normalizeText` (from `Libri.Text.Normalize`);
  - `TakeCalibre` on `FIdentifiers` overwrites `identifier:amazon` with Calibre's value but keeps a libri-only `identifier:openlibrary` and libri's `identifier:calibre`;
  - `KeepLibri` for every field returns the libri book unchanged.

- [ ] Step 2: Run `cabal test`. Expected: failures.

- [ ] Step 3: Implement.

- [ ] Step 4: Run `cabal test 2>&1 | tail -5`. Expected: `0 failures`.

- [ ] Step 5: Commit: `git commit -m "feat: field-level conflict resolution for Calibre re-import"`

### Task 6: Import driver

Files:
- Create: `src/Libri/CLI/CalibreImport.hs`
- Test: `test/CalibreImportDriverSpec.hs`

Interfaces:
- Consumes: everything above; `loadBooksWithErrors`, `saveBook`.
- Produces:
  - `type Ask = Text -> IO (Maybe Text)` (shows the prompt, returns the stripped answer; Nothing on EOF)
  - `data ImportSummary = ImportSummary { sumAdded, sumUnchanged, sumResolved, sumIgnored, sumDeletedInLibri, sumUnanswered, sumFailures :: Int } deriving (Show, Eq)`
  - `runCalibreImport :: Config -> Ask -> (Text -> IO ()) -> CalibreLibrary -> IO (Either LibriError ImportSummary)` (third argument prints a line)

Flow, in this order:
1. Load the collection with `loadBooksWithErrors`; any load error → `Left` naming the files, nothing written (Review Focus 1). Load the sync state; `Left` aborts.
2. Empty collection: add every book, record `SyncMapped` with its prints, make the library home, save state, return. No questions.
3. If this library has no sync entry (baseline) or its `lsHome` is `HomeUnanswered`: ask "Is <path> the Calibre library your collection came from? [y/n]". y → `setHomeLibrary`; n → `HomeNo`; EOF → stays `HomeUnanswered`, count one unanswered. Bare-id matching is enabled only when the result is `HomeYes`.
4. For each incoming book, `matchBook` against the live collection (updated after every add or merge):
   - `NoMatch`: on a baseline run, collect it as undecided; otherwise add it (save, record mapping).
   - `MatchPending`: collect as undecided.
   - `MatchByRef`/`MatchBareRef` on a baseline run: record mapping with incoming prints; change nothing. On a later run (library known, ref not recorded): same, record and count as unchanged.
   - `MatchMapped book stored`: `changedFields stored incoming` → `differingFields` against the libri book. None differing → update prints silently (`sumUnchanged`). Otherwise it is a conflict (below).
   - `MatchIsbnGuess book`: ask "[s]ame book / [n]ew book". s → record mapping, then treat every field in `differingFields [minBound..maxBound]` as a conflict. n → add. EOF → nothing added, unanswered.
   - `MatchIgnored` → `sumIgnored`; `MatchDeletedInLibri` → `sumDeletedInLibri`.
5. Conflict prompt: print the title, then one line per differing field with `fieldDisplay` for libri and Calibre; ask "[l] keep libri / [c] take Calibre / [f] field by field / [L] keep libri for all remaining". `f` asks per field "[l]/[c]", plus "[u] union" for `FTags`. Invalid answers re-ask. EOF keeps libri for every field not yet decided and counts one unanswered (Review Focus 4). After any outcome, store the incoming prints.
6. Undecided books (baseline new books and pending ones): list title, first author and Calibre id; ask "[a] add all / [i] ignore all / [o] one by one"; one by one asks "[a]dd / [i]gnore" per book. EOF → remaining become `SyncPending`, each counted unanswered.
7. Set this library's `lsPath` to `clPath`, then save the sync state once at the end (also after a save failure, so successful adds are recorded).

- [ ] Step 1: Write failing tests (temp dir; scripted `Ask` from an `IORef [Text]` that returns Nothing when exhausted; output collected into an `IORef`), building `CalibreLibrary` values in memory:
  - empty collection: 3 incoming books → 3 added, home yes, zero questions asked;
  - baseline: collection of 2 books with bare `identifier:calibre` `'1'`, `'2'`; incoming ids 1, 2, 3; answers `["y", "i"]` → books unchanged on disk, book 3 not added and recorded `SyncIgnored`; a second run with no answers asks nothing and adds nothing (the deleted-duplicates case);
  - later run, Calibre changed only comments of book 1, answer `"c"` → comments updated, tags untouched; a third run asks nothing;
  - same change, answer `"l"` → book unchanged, prints updated, no question next run;
  - field by field with EOF after the first field → first field applied, rest kept, `sumUnanswered == 1`;
  - non-interactive baseline (no answers): home stays unanswered, undecided books become `SyncPending`, `sumUnanswered > 0`, nothing added;
  - a corrupt book file in the collection → `Left`, no files written.

- [ ] Step 2: Run `cabal test`. Expected: compile failure / failing examples.

- [ ] Step 3: Implement `runCalibreImport`.

- [ ] Step 4: Run `cabal test 2>&1 | tail -5`. Expected: `0 failures`.

- [ ] Step 5: Commit: `git commit -m "feat: interactive, state-aware Calibre re-import"`

### Task 7: CLI wiring, cleanup and end-to-end check

Files:
- Modify: `src/Libri/CLI/Commands.hs` (`runImportCalibre`, help text "Import or re-import a Calibre library")
- Modify: `src/Libri/Storage/Yaml.hs` (remove `mergeBooks`), `test/YamlSpec.hs` (remove its block)
- Modify: `README.md` (Calibre bullet: "Calibre import and safe re-import"; one paragraph on what re-import asks)

Interfaces:
- Consumes: `importFromCalibre`, `runCalibreImport`, `readLineSafe`.

- [ ] Step 1: Replace `runImportCalibre`: read the library, call `runCalibreImport` with an `Ask` built from `TIO.putStr` + `hFlush stdout` + `readLineSafe`, print the summary as one line per non-zero count, `exitFailure` when `sumUnanswered > 0 || sumFailures > 0` or on `Left`.

- [ ] Step 2: Remove `mergeBooks` and its tests. Run `cabal build all 2>&1 | grep -E 'error|arning'` (expected: no output) and `cabal test 2>&1 | tail -5` (expected: `0 failures`).

- [ ] Step 3: End-to-end with the verify skill on a scratch copy (`cp -r data` and `cp -r "calibre-source/Calibre Library"` into the scratchpad; config pointing at the copy):
  - first run: asked the home question (answer y), then shown exactly three undecided books (Calibre ids 309, 351, 398); answer `i`. No book file changes (`diff -r` against the copy taken before the run).
  - second run: no questions, summary shows 0 added.
  - edit the scratch `metadata.db`: `UPDATE comments SET text = 'changed' WHERE book = 46;` third run shows one conflict listing only comments; answer `c`; only that book's comments change.
  - `--doctor` on the scratch copy reports no problems.

- [ ] Step 4: Commit: `git commit -m "feat: wire safe re-import into --import-calibre; remove mergeBooks"`

### Task 8: Remove the bogus provenance value

Files:
- Modify: the `data/books/` file of *The Elements of Typographic Style* (`grep -l "identifier:calibre: '9780881792126'" data/books/*.yaml`)

- [ ] Step 1: Remove the `identifier:calibre: '9780881792126'` line (if it leaves `custom:` empty, write `custom: {}`).
- [ ] Step 2: `libri --show <its id>` loads it; `libri --doctor` reports no problems.
- [ ] Step 3: Commit: `git add data && git commit -m "data: drop bogus Calibre provenance on The Elements of Typographic Style"`
