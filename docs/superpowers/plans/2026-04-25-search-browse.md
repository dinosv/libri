# Search and Browse Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a command bar with grouped views (by tag/author), tab-completion, and accent-folded fuzzy search to the TUI.

**Architecture:** Four independent modules built bottom-up: text normalisation (pure), command bar (pure parsing + state), grouped list (pure rendering data), then wiring into the existing TUI. Each module is tested before integration.

**Tech Stack:** Haskell, Brick TUI, unicode-transforms (new dependency), text-metrics (existing), hspec (testing)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `libri.cabal` | Modify | Add `unicode-transforms` dependency, new modules |
| `src/Libri/Text/Normalize.hs` | Create | `foldAccents`, `normalizeText` |
| `src/Libri/Search/Fuzzy.hs` | Modify | Use `normalizeText` in tokenize, raise thresholds |
| `src/Libri/TUI/CommandBar.hs` | Create | Command ADT, parser, tab-completion state, renderer |
| `src/Libri/TUI/Views/GroupedList.hs` | Create | `ListItem`, `buildGroupedList`, renderer, navigation |
| `src/Libri/Types.hs` | Modify | Add `Filter`, `GroupField`, new AppState fields, `ViewCommand` |
| `src/Libri/TUI/Widgets/Common.hs` | Modify | Add `commandBarAttr`, `sectionHeaderAttr`, `CommandBar` name |
| `src/Libri/TUI/App.hs` | Modify | Wire command bar, grouped views, filter logic |
| `test/NormalizeSpec.hs` | Create | Tests for accent folding |
| `test/CommandBarSpec.hs` | Create | Tests for command parsing and completion |
| `test/GroupedListSpec.hs` | Create | Tests for grouping logic and navigation |
| `test/SearchSpec.hs` | Modify | Add accent-folding search tests |
| `test/Main.hs` | Modify | Register new test modules |

---

### Task 1: Add unicode-transforms dependency

**Files:**
- Modify: `libri.cabal:38-63` (library build-depends)

- [ ] **Step 1: Add the dependency to cabal**

In `libri.cabal`, add `unicode-transforms` to the library `build-depends` block, after the `text-metrics` line:

```
                    , text-metrics >=0.3 && <0.4
                    , unicode-transforms >=0.4 && <0.5
                    , temporary >=1.3 && <2
```

- [ ] **Step 2: Verify it resolves**

Run: `cabal build --dry-run 2>&1 | head -20`
Expected: plan includes `unicode-transforms` without errors

- [ ] **Step 3: Commit**

```bash
git add libri.cabal
git commit -m "build: add unicode-transforms dependency for accent folding"
```

---

### Task 2: Create Libri.Text.Normalize module with tests

**Files:**
- Create: `src/Libri/Text/Normalize.hs`
- Create: `test/NormalizeSpec.hs`
- Modify: `test/Main.hs`
- Modify: `libri.cabal` (add module to exposed-modules and test other-modules)

- [ ] **Step 1: Register the module in cabal**

In `libri.cabal`, add to the library `exposed-modules` list (after `Libri.Search.Fuzzy`):

```
                    , Libri.Text.Normalize
```

Add to the test-suite `other-modules`:

```
                    , NormalizeSpec
```

Add `unicode-transforms` to the test-suite `build-depends`:

```
                    , unicode-transforms >=0.4 && <0.5
```

- [ ] **Step 2: Write the failing tests**

Create `test/NormalizeSpec.hs`:

```haskell
module NormalizeSpec (spec) where

import Libri.Text.Normalize
import Test.Hspec

spec :: Spec
spec = describe "Text.Normalize" $ do

  describe "foldAccents" $ do
    it "strips acute accents" $ do
      foldAccents "Óscar" `shouldBe` "Oscar"

    it "strips grave accents" $ do
      foldAccents "è" `shouldBe` "e"

    it "strips circumflex" $ do
      foldAccents "café" `shouldBe` "cafe"

    it "strips tilde from n" $ do
      foldAccents "niño" `shouldBe` "nino"

    it "strips diaeresis" $ do
      foldAccents "über" `shouldBe` "uber"

    it "leaves ASCII unchanged" $ do
      foldAccents "hello" `shouldBe` "hello"

    it "leaves numbers unchanged" $ do
      foldAccents "2024" `shouldBe` "2024"

    it "handles empty string" $ do
      foldAccents "" `shouldBe` ""

  describe "normalizeText" $ do
    it "lowercases and folds accents" $ do
      normalizeText "ÓSCAR" `shouldBe` "oscar"

    it "lowercases plain ASCII" $ do
      normalizeText "Hello World" `shouldBe` "hello world"

    it "combines lowercase and accent folding" $ do
      normalizeText "Café Über" `shouldBe` "cafe uber"
```

- [ ] **Step 3: Register test module in test Main.hs**

Add to `test/Main.hs`:

```haskell
import qualified NormalizeSpec
```

And in the `hspec` block:

```haskell
  NormalizeSpec.spec
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cabal test 2>&1 | tail -20`
Expected: compilation error -- `Libri.Text.Normalize` module not found

- [ ] **Step 5: Write the implementation**

Create `src/Libri/Text/Normalize.hs`:

```haskell
module Libri.Text.Normalize
  ( foldAccents
  , normalizeText
  ) where

import Data.Char (generalCategory, GeneralCategory(NonSpacingMark))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.ICU.Normalize2 as ICU

foldAccents :: Text -> Text
foldAccents = T.filter (not . isCombiningMark) . ICU.nfd
  where
    isCombiningMark c = generalCategory c == NonSpacingMark

normalizeText :: Text -> Text
normalizeText = foldAccents . T.toLower
```

Wait -- `unicode-transforms` uses `Data.Unicode.Normalize`, not `Data.Text.ICU.Normalize2`. Let me correct:

```haskell
module Libri.Text.Normalize
  ( foldAccents
  , normalizeText
  ) where

import Data.Char (generalCategory, GeneralCategory(NonSpacingMark))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Unicode.Normalize (NFD(..))

foldAccents :: Text -> Text
foldAccents = T.filter (not . isCombiningMark) . toNormalizedText NFD
  where
    isCombiningMark c = generalCategory c == NonSpacingMark

normalizeText :: Text -> Text
normalizeText = foldAccents . T.toLower
```

Actually, let me check the `unicode-transforms` API. The function is `Data.Text.Normalize.normalize` with `NFC`/`NFD` constructors. Let me write it correctly:

```haskell
module Libri.Text.Normalize
  ( foldAccents
  , normalizeText
  ) where

import Data.Char (generalCategory, GeneralCategory(NonSpacingMark))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Normalize as TN

foldAccents :: Text -> Text
foldAccents = T.filter (not . isCombiningMark) . TN.normalize TN.NFD
  where
    isCombiningMark c = generalCategory c == NonSpacingMark

normalizeText :: Text -> Text
normalizeText = foldAccents . T.toLower
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cabal test 2>&1 | tail -30`
Expected: all NormalizeSpec tests PASS

- [ ] **Step 7: Commit**

```bash
git add src/Libri/Text/Normalize.hs test/NormalizeSpec.hs test/Main.hs libri.cabal
git commit -m "feat: add Libri.Text.Normalize with accent folding"
```

---

### Task 3: Integrate normalizeText into fuzzy search and raise thresholds

**Files:**
- Modify: `src/Libri/Search/Fuzzy.hs`
- Modify: `test/SearchSpec.hs`

- [ ] **Step 1: Write the failing tests for accent-insensitive search**

Add to `test/SearchSpec.hs`, a new `makeBookWithTags` helper and tests. Add after the existing `makeBook` helper:

```haskell
makeBookWithTags :: Text -> Text -> [Text] -> [Text] -> Book
makeBookWithTags bid bookTitle bookAuthors bookTags =
  let timestamp = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = bid
       , _isbn = Nothing
       , _title = bookTitle
       , _authors = bookAuthors
       , _series = Nothing
       , _seriesIndex = Nothing
       , _publisher = Nothing
       , _published = Nothing
       , _tags = bookTags
       , _rating = Nothing
       , _comments = Nothing
       , _location = Nothing
       , _custom = Map.empty
       , _added = timestamp
       , _modified = timestamp
       }
```

Add a new describe block at the end of the spec:

```haskell
  describe "accent-insensitive search" $ do
    let accentBooks =
          [ makeBook "a1" "Rebaño" ["Óscar Contardo"]
          , makeBook "a2" "Being and Time" ["Martin Heidegger"]
          , makeBook "a3" "Café Society" ["Various"]
          ]

    it "finds accented title with plain ASCII query" $ do
      let results = searchBooks testThreshold "Rebano" accentBooks
      length results `shouldSatisfy` (> 0)
      case results of
        (r:_) -> _title r `shouldBe` "Rebaño"
        []    -> expectationFailure "expected results"

    it "finds accented author with plain ASCII query" $ do
      let results = searchBooks testThreshold "Oscar" accentBooks
      length results `shouldSatisfy` (> 0)
      case results of
        (r:_) -> _title r `shouldBe` "Rebaño"
        []    -> expectationFailure "expected results"

    it "finds accented title with uppercase query" $ do
      let results = searchBooks testThreshold "CAFE" accentBooks
      length results `shouldSatisfy` (> 0)
      case results of
        (r:_) -> _title r `shouldBe` "Café Society"
        []    -> expectationFailure "expected results"

  describe "tokenize normalizes accents" $ do
    it "folds accents during tokenization" $ do
      tokenize "Óscar" `shouldBe` ["oscar"]

    it "folds accents and lowercases" $ do
      tokenize "Café" `shouldBe` ["cafe"]
```

- [ ] **Step 2: Run tests to verify the new tests fail**

Run: `cabal test 2>&1 | grep -E "FAIL|PASS|✗|✔" | tail -20`
Expected: accent-insensitive tests FAIL (tokenize still uses T.toLower, not normalizeText)

- [ ] **Step 3: Integrate normalizeText into Fuzzy.hs**

In `src/Libri/Search/Fuzzy.hs`, add the import:

```haskell
import Libri.Text.Normalize (normalizeText)
```

Replace the `tokenize` function (lines 146-151):

```haskell
tokenize :: Text -> [Text]
tokenize =
  filter (not . T.null)
  . map normalizeText
  . T.split (not . isAlphaNum)
```

Also replace `T.toLower` in `bookContainsExact` (lines 42-43 and 48-50) with `normalizeText`:

```haskell
searchBooksExact :: Text -> [Book] -> [Book]
searchBooksExact query bks =
  let q = normalizeText (T.strip query)
  in filter (bookContainsExact q) bks

bookContainsExact :: Text -> Book -> Bool
bookContainsExact q book =
  q `T.isInfixOf` normalizeText (book ^. title)
  || any (T.isInfixOf q . normalizeText) (book ^. authors)
  || any (T.isInfixOf q . normalizeText) (book ^. tags)
```

Raise `minTokenMatchThreshold` (line 108-109):

```haskell
minTokenMatchThreshold :: Double
minTokenMatchThreshold = 0.65
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cabal test 2>&1 | tail -30`
Expected: all tests PASS including new accent tests

- [ ] **Step 5: Commit**

```bash
git add src/Libri/Search/Fuzzy.hs test/SearchSpec.hs
git commit -m "feat: accent-insensitive search with tighter relevance thresholds"
```

---

### Task 4: Add new types for Filter, GroupField, and ViewCommand

**Files:**
- Modify: `src/Libri/Types.hs:3-50` (export list), `src/Libri/Types.hs:167-198` (types and AppState)

- [ ] **Step 1: Add the new types and AppState fields**

In `src/Libri/Types.hs`, add to the export list after `SortOrder (..)`:

```haskell
    -- * Filter Types
  , Filter (..)
  , GroupField (..)
```

Add new lenses to the AppState Lenses section:

```haskell
  , activeFilter
  , groupMode
```

Add the type definitions after `SortOrder` (after line 173):

```haskell
-- | Filter for narrowing the book list
data Filter
  = FilterTag Text
  | FilterAuthor Text
  deriving (Show, Eq)

-- | Field to group books by
data GroupField = GroupByTag | GroupByAuthor
  deriving (Show, Eq)
```

Add `ViewCommand` to the `View` type (line 175-183):

```haskell
data View
  = ViewList
  | ViewSearch
  | ViewCommand
  | ViewAdd
  | ViewEdit BookId
  | ViewMove BookId
  | ViewHelp
  deriving (Show, Eq)
```

Add new fields to `AppState` (after `_sortOrder`, before the closing brace, line 194-195):

```haskell
  , _activeFilter :: Maybe Filter
  , _groupMode :: Maybe GroupField
```

The `makeLenses ''AppState` on line 198 will automatically generate the new lenses.

- [ ] **Step 2: Fix initialisation in App.hs**

In `src/Libri/TUI/App.hs`, add the new fields to the `initialState` AppState (after `_sortOrder = Ascending`):

```haskell
            , _activeFilter = Nothing
            , _groupMode = Nothing
```

- [ ] **Step 3: Verify it builds**

Run: `cabal build 2>&1 | tail -10`
Expected: builds with no errors

- [ ] **Step 4: Commit**

```bash
git add src/Libri/Types.hs src/Libri/TUI/App.hs
git commit -m "feat: add Filter, GroupField types and AppState fields"
```

---

### Task 5: Add new attributes and Name to Common.hs

**Files:**
- Modify: `src/Libri/TUI/Widgets/Common.hs`

- [ ] **Step 1: Add new attribute names and Name constructor**

In `src/Libri/TUI/Widgets/Common.hs`, add to the export list:

```haskell
  , commandBarAttr
  , sectionHeaderAttr
```

Add `CommandBarField` to the `Name` type:

```haskell
data Name
  = BookList
  | BookListViewport
  | BookDetails
  | SearchField
  | CommandBarField
  | AddForm
  | EditForm
  | LocationList
  | HelpView
  deriving (Eq, Ord, Show)
```

Add the new attributes to `theMap`:

```haskell
  , (commandBarAttr, fg brightYellow)
  , (sectionHeaderAttr, fg brightCyan `withStyle` bold)
```

Add the attribute name definitions:

```haskell
commandBarAttr :: AttrName
commandBarAttr = attrName "commandBar"

sectionHeaderAttr :: AttrName
sectionHeaderAttr = attrName "sectionHeader"
```

- [ ] **Step 2: Verify it builds**

Run: `cabal build 2>&1 | tail -5`
Expected: builds with no errors

- [ ] **Step 3: Commit**

```bash
git add src/Libri/TUI/Widgets/Common.hs
git commit -m "feat: add commandBar and sectionHeader attributes"
```

---

### Task 6: Create CommandBar module with tests

**Files:**
- Create: `src/Libri/TUI/CommandBar.hs`
- Create: `test/CommandBarSpec.hs`
- Modify: `libri.cabal` (add modules)
- Modify: `test/Main.hs`

- [ ] **Step 1: Register modules in cabal**

Add `Libri.TUI.CommandBar` to library `exposed-modules`.
Add `CommandBarSpec` to test-suite `other-modules`.

- [ ] **Step 2: Write the failing tests**

Create `test/CommandBarSpec.hs`:

```haskell
module CommandBarSpec (spec) where

import Libri.TUI.CommandBar
import Libri.Types (SortField(..))
import Test.Hspec

spec :: Spec
spec = describe "CommandBar" $ do

  describe "parseCommand" $ do
    it "parses tag filter" $ do
      parseCommand "tag Philosophy" `shouldBe` CmdFilterTag "Philosophy"

    it "parses author filter" $ do
      parseCommand "author Eco" `shouldBe` CmdFilterAuthor "Eco"

    it "parses group by tag" $ do
      parseCommand "group tag" `shouldBe` CmdGroup GroupByTag

    it "parses group by author" $ do
      parseCommand "group author" `shouldBe` CmdGroup GroupByAuthor

    it "parses group none" $ do
      parseCommand "group none" `shouldBe` CmdGroupNone

    it "parses clear" $ do
      parseCommand "clear" `shouldBe` CmdClear

    it "parses sort title" $ do
      parseCommand "sort title" `shouldBe` CmdSort SortByTitle

    it "parses sort author" $ do
      parseCommand "sort author" `shouldBe` CmdSort SortByAuthor

    it "parses sort date" $ do
      parseCommand "sort date" `shouldBe` CmdSort SortByDate

    it "returns unknown for invalid command" $ do
      parseCommand "foobar" `shouldBe` CmdUnknown "foobar"

    it "trims whitespace from arguments" $ do
      parseCommand "tag  Philosophy  " `shouldBe` CmdFilterTag "Philosophy"

    it "handles empty input" $ do
      parseCommand "" `shouldBe` CmdUnknown ""

  describe "tab completion" $ do
    let candidates = ["Philosophy", "History", "Art", "Poetry", "Politics"]
        cbs = initCommandBarState candidates []

    it "completes first match on Tab" $ do
      let cbs' = cbs { cbsInput = "tag Ph" }
          completed = completeNext cbs'
      cbsInput completed `shouldBe` "tag Philosophy"

    it "cycles to next match on repeated Tab" $ do
      let cbs' = cbs { cbsInput = "tag P" }
          c1 = completeNext cbs'
          c2 = completeNext c1
      cbsInput c1 `shouldSatisfy` (\t -> t == "tag Philosophy" || t == "tag Poetry" || t == "tag Politics")
      cbsInput c2 `shouldSatisfy` (\t -> t /= cbsInput c1)

    it "shows all options when argument is empty" $ do
      let cbs' = cbs { cbsInput = "tag " }
          c1 = completeNext cbs'
      cbsInput c1 `shouldSatisfy` (/= "tag ")

    it "wraps around to first match" $ do
      let cbs' = cbs { cbsInput = "tag Art" }
          c1 = completeNext cbs'
          c2 = completeNext c1
      cbsInput c1 `shouldBe` "tag Art"
      cbsInput c2 `shouldBe` "tag Art"
```

- [ ] **Step 3: Register test module in test Main.hs**

Add to `test/Main.hs`:

```haskell
import qualified CommandBarSpec
```

And in the `hspec` block:

```haskell
  CommandBarSpec.spec
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cabal test 2>&1 | tail -5`
Expected: compilation error -- `Libri.TUI.CommandBar` module not found

- [ ] **Step 5: Write the implementation**

Create `src/Libri/TUI/CommandBar.hs`:

```haskell
module Libri.TUI.CommandBar
  ( Command (..)
  , CommandBarState (..)
  , parseCommand
  , initCommandBarState
  , completeNext
  , renderCommandBar
  ) where

import Brick
import Data.Text (Text)
import qualified Data.Text as T
import Libri.Text.Normalize (normalizeText)
import Libri.TUI.Widgets.Common (Name, commandBarAttr, helpAttr)
import Libri.Types (SortField(..), GroupField(..))

data Command
  = CmdFilterTag Text
  | CmdFilterAuthor Text
  | CmdGroup GroupField
  | CmdGroupNone
  | CmdSort SortField
  | CmdClear
  | CmdUnknown Text
  deriving (Show, Eq)

-- Note: CmdGroupNone is separate from CmdClear.
-- CmdGroupNone only clears grouping. CmdClear clears both filter and grouping.

data CommandBarState = CommandBarState
  { cbsInput :: Text
  , cbsTagCandidates :: [Text]
  , cbsAuthorCandidates :: [Text]
  , cbsCompletionIndex :: Maybe Int
  , cbsLastPrefix :: Text
  }
  deriving (Show)

initCommandBarState :: [Text] -> [Text] -> CommandBarState
initCommandBarState tagCandidates authorCandidates = CommandBarState
  { cbsInput = ""
  , cbsTagCandidates = tagCandidates
  , cbsAuthorCandidates = authorCandidates
  , cbsCompletionIndex = Nothing
  , cbsLastPrefix = ""
  }

parseCommand :: Text -> Command
parseCommand raw =
  let stripped = T.strip raw
      (cmd, rest) = T.breakOn " " stripped
      arg = T.strip (T.drop 1 rest)
  in case T.toLower cmd of
    "tag"    | not (T.null arg) -> CmdFilterTag arg
    "author" | not (T.null arg) -> CmdFilterAuthor arg
    "group"  -> case T.toLower arg of
      "tag"    -> CmdGroup GroupByTag
      "author" -> CmdGroup GroupByAuthor
      "none"   -> CmdGroupNone
      _        -> CmdUnknown stripped
    "sort"   -> case T.toLower arg of
      "title"  -> CmdSort SortByTitle
      "author" -> CmdSort SortByAuthor
      "date"   -> CmdSort SortByDate
      _        -> CmdUnknown stripped
    "clear"  -> CmdClear
    _        -> CmdUnknown stripped

completeNext :: CommandBarState -> CommandBarState
completeNext cbs =
  let input = cbsInput cbs
      (cmd, rest) = T.breakOn " " input
      hasSpace = T.length rest > 0
  in if not hasSpace
       then cbs
       else
         let prefix = if cbsCompletionIndex cbs == Nothing
                        then T.strip (T.drop 1 rest)
                        else cbsLastPrefix
             candidates = case T.toLower cmd of
               "tag"    -> cbsTagCandidates cbs
               "author" -> cbsAuthorCandidates cbs
               _        -> []
             normPrefix = normalizeText prefix
             matches = if T.null normPrefix
                         then candidates
                         else filter (\c -> normPrefix `T.isPrefixOf` normalizeText c) candidates
         in if null matches
              then cbs
              else
                let idx = case cbsCompletionIndex cbs of
                      Nothing -> 0
                      Just i  -> (i + 1) `mod` length matches
                    chosen = matches !! idx
                in cbs
                  { cbsInput = cmd <> " " <> chosen
                  , cbsCompletionIndex = Just idx
                  , cbsLastPrefix = prefix
                  }

renderCommandBar :: CommandBarState -> Widget Name
renderCommandBar cbs =
  withAttr commandBarAttr $
    hBox
      [ txt ":"
      , txt (cbsInput cbs)
      , txt "▋"
      ]
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cabal test 2>&1 | tail -30`
Expected: all CommandBarSpec tests PASS

- [ ] **Step 7: Commit**

```bash
git add src/Libri/TUI/CommandBar.hs test/CommandBarSpec.hs test/Main.hs libri.cabal
git commit -m "feat: add CommandBar with parsing and tab-completion"
```

---

### Task 7: Create GroupedList module with tests

**Files:**
- Create: `src/Libri/TUI/Views/GroupedList.hs`
- Create: `test/GroupedListSpec.hs`
- Modify: `libri.cabal` (add modules)
- Modify: `test/Main.hs`

- [ ] **Step 1: Register modules in cabal**

Add `Libri.TUI.Views.GroupedList` to library `exposed-modules`.
Add `GroupedListSpec` to test-suite `other-modules`.

- [ ] **Step 2: Write the failing tests**

Create `test/GroupedListSpec.hs`:

```haskell
module GroupedListSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Libri.TUI.Views.GroupedList
import Libri.Types
import Test.Hspec

makeBook :: Text -> Text -> [Text] -> [Text] -> Book
makeBook bid bookTitle bookAuthors bookTags =
  let timestamp = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = bid
       , _isbn = Nothing
       , _title = bookTitle
       , _authors = bookAuthors
       , _series = Nothing
       , _seriesIndex = Nothing
       , _publisher = Nothing
       , _published = Nothing
       , _tags = bookTags
       , _rating = Nothing
       , _comments = Nothing
       , _location = Nothing
       , _custom = Map.empty
       , _added = timestamp
       , _modified = timestamp
       }

spec :: Spec
spec = describe "GroupedList" $ do
  let book1 = makeBook "1" "Being and Time" ["Heidegger"] ["Philosophy"]
      book2 = makeBook "2" "Rebaño" ["Contardo"] ["History", "Religion"]
      book3 = makeBook "3" "The Visual Display" ["Tufte"] ["Art"]
      book4 = makeBook "4" "Untitled" ["Unknown"] []
      testBooks = [book1, book2, book3, book4]

  describe "buildGroupedList" $ do
    it "groups books by tag with section headers" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          headers = [t | SectionHeader t _ <- items]
      headers `shouldSatisfy` elem "Art"
      headers `shouldSatisfy` elem "History"
      headers `shouldSatisfy` elem "Philosophy"
      headers `shouldSatisfy` elem "Religion"
      headers `shouldSatisfy` elem "(Untagged)"

    it "puts untagged books at the end" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          lastHeader = last [t | SectionHeader t _ <- items]
      lastHeader `shouldBe` "(Untagged)"

    it "shows correct count in headers" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          artHeader = [(t, n) | SectionHeader t n <- items, t == "Art"]
      artHeader `shouldBe` [("Art", 1)]

    it "duplicates books with multiple tags" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          bookRows = [b | BookRow b <- items]
      length bookRows `shouldSatisfy` (> length testBooks)

    it "groups books by author" $ do
      let items = buildGroupedList GroupByAuthor SortByTitle Ascending testBooks
          headers = [t | SectionHeader t _ <- items]
      headers `shouldSatisfy` elem "Heidegger"
      headers `shouldSatisfy` elem "Contardo"

    it "sorts sections alphabetically" $ do
      let items = buildGroupedList GroupByTag SortByTitle Ascending testBooks
          headers = [t | SectionHeader t _ <- items, t /= "(Untagged)"]
      headers `shouldBe` ["Art", "History", "Philosophy", "Religion"]

  describe "navigation" $ do
    it "nextSelectableIndex skips headers" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  , SectionHeader "Philosophy" 1
                  , BookRow book1
                  ]
      nextSelectableIndex items 1 `shouldBe` 3

    it "prevSelectableIndex skips headers" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  , SectionHeader "Philosophy" 1
                  , BookRow book1
                  ]
      prevSelectableIndex items 3 `shouldBe` 1

    it "nextSelectableIndex stays at last book" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  ]
      nextSelectableIndex items 1 `shouldBe` 1

    it "prevSelectableIndex stays at first book" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  ]
      prevSelectableIndex items 1 `shouldBe` 1

    it "firstSelectableIndex finds first book row" $ do
      let items = [ SectionHeader "Art" 1
                  , BookRow book3
                  , SectionHeader "Philosophy" 1
                  , BookRow book1
                  ]
      firstSelectableIndex items `shouldBe` 1
```

- [ ] **Step 3: Register test module in test Main.hs**

Add to `test/Main.hs`:

```haskell
import qualified GroupedListSpec
```

And in the `hspec` block:

```haskell
  GroupedListSpec.spec
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cabal test 2>&1 | tail -5`
Expected: compilation error -- `Libri.TUI.Views.GroupedList` module not found

- [ ] **Step 5: Write the implementation**

Create `src/Libri/TUI/Views/GroupedList.hs`:

```haskell
module Libri.TUI.Views.GroupedList
  ( ListItem (..)
  , buildGroupedList
  , renderGroupedList
  , nextSelectableIndex
  , prevSelectableIndex
  , firstSelectableIndex
  ) where

import Brick
import Data.List (sortBy)
import qualified Data.Map.Strict as Map
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import Lens.Micro ((^.))
import Libri.TUI.Widgets.Common
import Libri.Types

data ListItem
  = SectionHeader Text Int
  | BookRow Book
  deriving (Show, Eq)

buildGroupedList :: GroupField -> SortField -> SortOrder -> [Book] -> [ListItem]
buildGroupedList field sortF sortO bks =
  let grouped = groupBooks field bks
      sortedKeys = sortBy (comparing fst)
                   [(k, vs) | (k, vs) <- Map.toList grouped, k /= "(Untagged)"]
      untagged = Map.lookup "(Untagged)" grouped
      sections = map (buildSection sortF sortO) sortedKeys
      untaggedSection = case untagged of
        Nothing -> []
        Just us -> buildSection sortF sortO ("(Untagged)", us)
  in concat sections ++ untaggedSection

groupBooks :: GroupField -> [Book] -> Map.Map Text [Book]
groupBooks GroupByTag bks = foldr addByTag Map.empty bks
  where
    addByTag book acc =
      case book ^. tags of
        [] -> Map.insertWith (++) "(Untagged)" [book] acc
        ts -> foldr (\t m -> Map.insertWith (++) t [book] m) acc ts
groupBooks GroupByAuthor bks = foldr addByAuthor Map.empty bks
  where
    addByAuthor book acc =
      case book ^. authors of
        [] -> Map.insertWith (++) "(Unknown)" [book] acc
        as -> foldr (\a m -> Map.insertWith (++) a [book] m) acc as

buildSection :: SortField -> SortOrder -> (Text, [Book]) -> [ListItem]
buildSection sortF sortO (name, bks) =
  let sorted = applySortOrder' sortF sortO bks
  in SectionHeader name (length bks) : map BookRow sorted

applySortOrder' :: SortField -> SortOrder -> [Book] -> [Book]
applySortOrder' field order bks =
  let cmp = case field of
        SortByTitle  -> comparing (T.toLower . (^. title))
        SortByAuthor -> comparing (T.toLower . head' . (^. authors))
        SortByDate   -> comparing (^. published)
      sorted = sortBy cmp bks
  in case order of
       Ascending  -> sorted
       Descending -> reverse sorted
  where
    head' [] = ""
    head' (x:_) = x

renderGroupedList :: [ListItem] -> Int -> Widget Name
renderGroupedList items selectedIdx =
  if null items
    then txt "No books to display"
    else withVScrollBars OnRight $
           viewport BookListViewport Vertical $
             vBox $ zipWith (renderItem selectedIdx) [0..] items

renderItem :: Int -> Int -> ListItem -> Widget Name
renderItem _ _ (SectionHeader name count) =
  withAttr sectionHeaderAttr $
    padRight Max $
      txt $ "── " <> name <> " (" <> T.pack (show count) <> ") " <>
            T.replicate 40 "─"
renderItem selectedIdx idx (BookRow book) =
  let isSelected = idx == selectedIdx
      attr = if isSelected then selectedAttr else mempty
      prefix = if isSelected then "> " else "  "
      titleText = truncateText 35 (book ^. title)
      authorText = truncateText 25 $ formatAuthors' (book ^. authors)
      row = withAttr attr $
              hBox
                [ txt prefix
                , padRight Max $ txt titleText
                , padRight (Pad 2) $ txt authorText
                ]
  in if isSelected then visible row else row

truncateText :: Int -> Text -> Text
truncateText maxLen t
  | T.length t <= maxLen = t
  | otherwise = T.take (maxLen - 1) t <> "…"

formatAuthors' :: [Text] -> Text
formatAuthors' [] = "Unknown"
formatAuthors' [a] = a
formatAuthors' (a:_) = a <> " et al."

nextSelectableIndex :: [ListItem] -> Int -> Int
nextSelectableIndex items current =
  let candidates = [i | (i, item) <- zip [0..] items, i > current, isBookRow item]
  in case candidates of
       (x:_) -> x
       []    -> current

prevSelectableIndex :: [ListItem] -> Int -> Int
prevSelectableIndex items current =
  let candidates = reverse [i | (i, item) <- zip [0..] items, i < current, isBookRow item]
  in case candidates of
       (x:_) -> x
       []    -> current

firstSelectableIndex :: [ListItem] -> Int
firstSelectableIndex items =
  case [i | (i, item) <- zip [0..] items, isBookRow item] of
    (x:_) -> x
    []    -> 0

isBookRow :: ListItem -> Bool
isBookRow (BookRow _) = True
isBookRow _ = False
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cabal test 2>&1 | tail -30`
Expected: all GroupedListSpec tests PASS

- [ ] **Step 7: Commit**

```bash
git add src/Libri/TUI/Views/GroupedList.hs test/GroupedListSpec.hs test/Main.hs libri.cabal
git commit -m "feat: add GroupedList with section headers and skip-navigation"
```

---

### Task 8: Wire command bar into App.hs

**Files:**
- Modify: `src/Libri/TUI/App.hs`

This is the integration task. It wires the command bar into the TUI event loop, connects filter/group state to `getVisibleBooks`, and switches between flat and grouped rendering.

- [ ] **Step 1: Add imports**

Add to `src/Libri/TUI/App.hs` imports:

```haskell
import Libri.TUI.CommandBar
import Libri.TUI.Views.GroupedList (ListItem(..), buildGroupedList, renderGroupedList, nextSelectableIndex, prevSelectableIndex, firstSelectableIndex)
import Libri.Text.Normalize (normalizeText)
```

- [ ] **Step 2: Add CommandBarState to TUIState**

Add a new field to `TUIState`:

```haskell
  , tuiCommandBarState :: Maybe CommandBarState
```

Initialise it in `runTUI`:

```haskell
        , tuiCommandBarState = Nothing
```

- [ ] **Step 3: Update getVisibleBooks to apply filters**

Replace the `getVisibleBooks` function:

```haskell
getVisibleBooks :: AppState -> [Book]
getVisibleBooks st =
  let query = st ^. searchQuery
      filtered = applyFilter (st ^. activeFilter) (st ^. books)
      sorted = applySortOrder (st ^. sortField) (st ^. sortOrder) filtered
      threshold = st ^. config . fuzzyThreshold
  in if T.null query
       then sorted
       else searchBooks threshold query sorted

applyFilter :: Maybe Filter -> [Book] -> [Book]
applyFilter Nothing bks = bks
applyFilter (Just (FilterTag t)) bks =
  let normT = normalizeText t
  in filter (\b -> any (\tag -> normT `T.isInfixOf` normalizeText tag) (b ^. tags)) bks
applyFilter (Just (FilterAuthor a)) bks =
  let normA = normalizeText a
  in filter (\b -> any (\auth -> normA `T.isInfixOf` normalizeText auth) (b ^. authors)) bks
```

- [ ] **Step 4: Update drawUI for grouped views and command bar**

In `drawUI`, every call to `mainLayout` needs the new command bar parameter. Update all four occurrences (ViewAdd fallback, ViewEdit fallback, ViewMove fallback, and the default case) to pass `(tuiCommandBarState st)` as the fifth argument:

```haskell
       _ -> [mainLayout appSt visibleBooks selectedBook (tuiMessage st)
               (tuiCommandBarState st)]
```

Apply the same change to the three `Nothing ->` fallback branches above it.

Update `mainLayout` signature to accept the command bar state:

```haskell
mainLayout :: AppState -> [Book] -> Maybe Book -> Maybe Text -> Maybe CommandBarState -> Widget Name
mainLayout st visibleBooks selectedBook msg mCbs =
```

In the main content area, switch between flat and grouped rendering:

```haskell
        [ -- Left: Book list
          hLimitPercent 50 $
            titledBorder ("Books" <> searchIndicator st <> filterIndicator st) $
              vBox
                [ padAll 1 $ renderBookArea st visibleBooks
                , hBorder
                , renderSearchOrCommandBar st mCbs
                ]
```

Add the helper functions:

```haskell
renderBookArea :: AppState -> [Book] -> Widget Name
renderBookArea st bks =
  case st ^. groupMode of
    Nothing -> renderBookList bks (st ^. selectedIndex)
    Just gf ->
      let items = buildGroupedList gf (st ^. sortField) (st ^. sortOrder) bks
      in renderGroupedList items (st ^. selectedIndex)

filterIndicator :: AppState -> Text
filterIndicator st =
  case st ^. activeFilter of
    Nothing -> ""
    Just (FilterTag t)    -> " [tag:" <> t <> "]"
    Just (FilterAuthor a) -> " [author:" <> a <> "]"

renderSearchOrCommandBar :: AppState -> Maybe CommandBarState -> Widget Name
renderSearchOrCommandBar st mCbs =
  padAll 1 $ case st ^. currentView of
    ViewSearch  -> renderSearchBar (st ^. searchQuery) True
    ViewCommand -> case mCbs of
      Just cbs -> renderCommandBar cbs
      Nothing  -> renderSearchBar (st ^. searchQuery) False
    _ -> renderSearchBar (st ^. searchQuery) False
```

- [ ] **Step 5: Handle `:` keybinding to open command bar**

In `handleListViewEvent`, add a new case before the `-- Help` case:

```haskell
    -- Command bar
    VtyEvent (V.EvKey (V.KChar ':') []) ->
      let allTags = nub $ concatMap (^. tags) (appSt ^. books)
          allAuthors = nub $ concatMap (^. authors) (appSt ^. books)
          cbs = initCommandBarState (sortBy compare allTags) (sortBy compare allAuthors)
      in put $ st { tuiAppState = appSt & currentView .~ ViewCommand
                  , tuiCommandBarState = Just cbs
                  , tuiMessage = Just "Type command, Tab to complete, Enter to execute"
                  }
```

- [ ] **Step 6: Handle command bar input events**

Add a new case in `handleEvent` for `ViewCommand`, before the `ViewList` case:

```haskell
    ViewCommand -> handleCommandBarEvent ev st
```

Add the handler function:

```haskell
handleCommandBarEvent :: BrickEvent Name e -> TUIState -> EventM Name TUIState ()
handleCommandBarEvent ev st = do
  let appSt = tuiAppState st

  case tuiCommandBarState st of
    Nothing -> put $ st { tuiAppState = appSt & currentView .~ ViewList }
    Just cbs -> case ev of
      VtyEvent (V.EvKey V.KEsc []) ->
        put $ st { tuiAppState = appSt & currentView .~ ViewList
                 , tuiCommandBarState = Nothing
                 , tuiMessage = Nothing
                 }

      VtyEvent (V.EvKey V.KEnter []) ->
        let cmd = parseCommand (cbsInput cbs)
        in executeCommand cmd st

      VtyEvent (V.EvKey (V.KChar '\t') []) ->
        put $ st { tuiCommandBarState = Just (completeNext cbs) }

      VtyEvent (V.EvKey V.KBS []) ->
        let newInput = T.dropEnd 1 (cbsInput cbs)
        in put $ st { tuiCommandBarState = Just $ cbs
                        { cbsInput = newInput
                        , cbsCompletionIndex = Nothing
                        }
                    }

      VtyEvent (V.EvKey (V.KChar c) []) ->
        let newInput = cbsInput cbs <> T.singleton c
        in put $ st { tuiCommandBarState = Just $ cbs
                        { cbsInput = newInput
                        , cbsCompletionIndex = Nothing
                        }
                    }

      _ -> pure ()
```

- [ ] **Step 7: Add command execution**

```haskell
executeCommand :: Command -> TUIState -> EventM Name TUIState ()
executeCommand cmd st = do
  let appSt = tuiAppState st
  case cmd of
    CmdFilterTag t ->
      put $ st { tuiAppState = appSt & activeFilter .~ Just (FilterTag t)
                                      & currentView .~ ViewList
                                      & selectedIndex .~ 0
               , tuiCommandBarState = Nothing
               , tuiMessage = Just $ "Filter: tag = " <> t
               }
    CmdFilterAuthor a ->
      put $ st { tuiAppState = appSt & activeFilter .~ Just (FilterAuthor a)
                                      & currentView .~ ViewList
                                      & selectedIndex .~ 0
               , tuiCommandBarState = Nothing
               , tuiMessage = Just $ "Filter: author = " <> a
               }
    CmdGroup gf ->
      let newAppSt = appSt & groupMode .~ Just gf
                            & currentView .~ ViewList
                            & selectedIndex .~ 0
          visibleBks = getVisibleBooks newAppSt
          items = buildGroupedList gf (newAppSt ^. sortField) (newAppSt ^. sortOrder) visibleBks
          firstIdx = firstSelectableIndex items
      in put $ st { tuiAppState = newAppSt & selectedIndex .~ firstIdx
                  , tuiCommandBarState = Nothing
                  , tuiMessage = Just $ "Grouped by " <> groupFieldName gf
                  }
    CmdGroupNone ->
      put $ st { tuiAppState = appSt & groupMode .~ Nothing
                                      & currentView .~ ViewList
                                      & selectedIndex .~ 0
               , tuiCommandBarState = Nothing
               , tuiMessage = Just "Grouping cleared"
               }
    CmdSort sf ->
      put $ st { tuiAppState = appSt & sortField .~ sf
                                      & currentView .~ ViewList
                                      & selectedIndex .~ 0
               , tuiCommandBarState = Nothing
               , tuiMessage = Just $ "Sorted by " <> sortFieldName sf
               }
    CmdClear ->
      put $ st { tuiAppState = appSt & activeFilter .~ Nothing
                                      & groupMode .~ Nothing
                                      & currentView .~ ViewList
                                      & selectedIndex .~ 0
               , tuiCommandBarState = Nothing
               , tuiMessage = Just "Filters and grouping cleared"
               }
    CmdUnknown t ->
      put $ st { tuiAppState = appSt & currentView .~ ViewList
               , tuiCommandBarState = Nothing
               , tuiMessage = Just $ "Unknown command: " <> t
               }

groupFieldName :: GroupField -> Text
groupFieldName GroupByTag = "tag"
groupFieldName GroupByAuthor = "author"

sortFieldName :: SortField -> Text
sortFieldName SortByTitle = "title"
sortFieldName SortByAuthor = "author"
sortFieldName SortByDate = "date"
```

- [ ] **Step 8: Update navigation for grouped mode**

In `handleListViewEvent`, the j/k/up/down navigation needs to use `nextSelectableIndex`/`prevSelectableIndex` when in grouped mode. Replace the navigation cases:

```haskell
    -- Navigation
    VtyEvent (V.EvKey V.KUp []) -> navigateUp st appSt visibleBooks
    VtyEvent (V.EvKey V.KDown []) -> navigateDown st appSt visibleBooks
    VtyEvent (V.EvKey (V.KChar 'k') []) -> navigateUp st appSt visibleBooks
    VtyEvent (V.EvKey (V.KChar 'j') []) -> navigateDown st appSt visibleBooks
```

Add the navigation helpers:

```haskell
navigateUp :: TUIState -> AppState -> [Book] -> EventM Name TUIState ()
navigateUp st appSt visibleBks =
  case appSt ^. groupMode of
    Nothing ->
      put $ st { tuiAppState = appSt & selectedIndex %~ max 0 . subtract 1 }
    Just gf ->
      let items = buildGroupedList gf (appSt ^. sortField) (appSt ^. sortOrder) visibleBks
          newIdx = prevSelectableIndex items (appSt ^. selectedIndex)
      in put $ st { tuiAppState = appSt & selectedIndex .~ newIdx }

navigateDown :: TUIState -> AppState -> [Book] -> EventM Name TUIState ()
navigateDown st appSt visibleBks =
  case appSt ^. groupMode of
    Nothing ->
      put $ st { tuiAppState = appSt & selectedIndex %~ min (length visibleBks - 1) . (+ 1) }
    Just gf ->
      let items = buildGroupedList gf (appSt ^. sortField) (appSt ^. sortOrder) visibleBks
          newIdx = nextSelectableIndex items (appSt ^. selectedIndex)
      in put $ st { tuiAppState = appSt & selectedIndex .~ newIdx }
```

Also update `getSelectedBook` to work in grouped mode:

```haskell
getSelectedBook :: AppState -> [Book] -> Maybe Book
getSelectedBook st visibleBks =
  case st ^. groupMode of
    Nothing ->
      let idx = st ^. selectedIndex
      in if idx >= 0 && idx < length visibleBks
           then Just (visibleBks !! idx)
           else Nothing
    Just gf ->
      let items = buildGroupedList gf (st ^. sortField) (st ^. sortOrder) visibleBks
          idx = st ^. selectedIndex
      in case drop idx items of
           (BookRow b : _) -> Just b
           _ -> Nothing
```

- [ ] **Step 9: Verify it builds and basic functionality works**

Run: `cabal build 2>&1 | tail -10`
Expected: builds with no errors

Run: `cabal test 2>&1 | tail -5`
Expected: all tests PASS

- [ ] **Step 10: Commit**

```bash
git add src/Libri/TUI/App.hs
git commit -m "feat: wire command bar, grouped views, and filtering into TUI"
```

---

### Task 9: Update footer help text

**Files:**
- Modify: `src/Libri/TUI/App.hs` (renderFooter function)

- [ ] **Step 1: Add `:` to the help bar**

Update the `renderFooter` function's `keyHelp` list to include the command bar:

```haskell
          [ keyHelp
              [ ("/", "Search")
              , (":", "Command")
              , ("a", "Add")
              , ("e", "Edit")
              , ("d", "Delete")
              , ("m", "Move")
              , ("?", "Help")
              , ("q", "Quit")
              ]
```

- [ ] **Step 2: Verify it builds**

Run: `cabal build 2>&1 | tail -5`
Expected: builds with no errors

- [ ] **Step 3: Commit**

```bash
git add src/Libri/TUI/App.hs
git commit -m "feat: add command bar shortcut to footer help"
```

---

### Task 10: Manual smoke test

**Files:** None (testing only)

- [ ] **Step 1: Launch the TUI and verify basic functionality**

Run: `cabal run libri`

Test these scenarios:
1. Press `/`, type "contardo", verify accent-insensitive match shows Rebaño
2. Press Esc, then `:`, type "group tag", press Enter -- verify grouped view with section headers
3. Navigate with j/k -- verify cursor skips section headers
4. Press `:`, type "tag ", press Tab repeatedly -- verify completion cycles through tags
5. Press `:`, type "clear", press Enter -- verify flat list returns
6. Press `:`, type "author Eco", press Enter -- verify filter shows only Eco's books
7. Press `:`, type "sort date", press Enter -- verify sort changes

- [ ] **Step 2: Fix any issues found during smoke test**

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: smoke test corrections"
```
