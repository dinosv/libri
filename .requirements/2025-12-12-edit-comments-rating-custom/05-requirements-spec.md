# Edit Comments, Rating, and Custom Fields

**Created:** 2025-12-12
**Status:** draft
**Last Updated:** 2025-12-12

---

## Overview

Extend the libri TUI Add/Edit book form to support editing three additional book properties:

1. **Rating** - A 1-5 numeric rating, entered directly in the form
2. **Comments** - Free-form text, edited via external editor ($EDITOR or vim)
3. **Custom Fields** - Key-value pairs with full management (add, edit, delete)

These fields will be added at the end of the existing 7-field form, bringing the total to 10 navigable fields. The implementation follows existing patterns in the codebase for consistency.

---

## Implementation Strategy

### Recommended Skill
**Skill:** `developer` (or direct implementation)

**Rationale:**
- Code implementation extending existing Haskell/Brick TUI
- Files to modify: AddBook.hs, App.hs
- Task type: Feature extension
- Follows established patterns in codebase

---

## Requirements

### Functional Requirements

1. **Rating Field**
   - Accept numeric input 1-5 only
   - Ignore any other characters
   - Display current rating or empty if unset
   - Save as `Maybe Int` in Book type

2. **Comments Field**
   - Display truncated preview of existing comments (max ~50 chars)
   - Show "[Ctrl+E] Edit" hint when field is selected
   - Ctrl+E opens external editor ($EDITOR env var, fallback to vim)
   - Editor opens with current comments content
   - On editor close, capture updated content

3. **Custom Fields**
   - Display list of existing key-value pairs
   - Vim-like navigation within the list (j/k to move)
   - 'a' to add new field (prompts for key, then value)
   - Enter to edit selected field's value
   - 'd' to delete selected field
   - Esc to exit custom field editing mode

4. **Data Preservation**
   - When editing existing book, load all current values
   - Preserve values user didn't modify
   - Save all fields including rating, comments, custom

---

## Technical Implementation

### Field Layout (Extended Form)

```
Field 0: ISBN
Field 1: Title
Field 2: Authors (comma-separated)
Field 3: Publisher
Field 4: Published (year)
Field 5: Location
Field 6: Tags (comma-separated)
Field 7: Rating (1-5)              <- NEW
Field 8: Comments [Ctrl+E]         <- NEW
Field 9: Custom Fields [Enter]     <- NEW
```

### Files to Modify

#### 1. `src/Libri/TUI/Views/AddBook.hs`

**AddBookState changes:**
```haskell
data AddBookState = AddBookState
  { absIsbn :: Text
  , absTitle :: Text
  , absAuthors :: Text
  , absPublisher :: Text
  , absPublished :: Text
  , absLocation :: Text
  , absTags :: Text
  , absRating :: Text              -- NEW: "1"-"5" or ""
  , absComments :: Text            -- NEW: full text, display truncated
  , absCustomFields :: [(Text, Text)]  -- NEW: list of (key, value)
  , absCustomFieldIdx :: Int       -- NEW: selected custom field index
  , absEditingCustom :: Bool       -- NEW: whether in custom field mode
  , absCurrentField :: Int         -- Change mod from 7 to 10
  , absIsEdit :: Bool
  , absOriginalId :: Maybe BookId
  }
```

**initEditBookState changes:**
```haskell
initEditBookState book = AddBookState
  { -- ... existing fields ...
  , absRating = maybe "" (T.pack . show) (book ^. rating)
  , absComments = maybe "" id (book ^. comments)
  , absCustomFields = Map.toList $ Map.map valueToText (book ^. custom)
  -- ... rest ...
  }
```

**updateCurrentField changes:**
```haskell
updateCurrentField f st = case absCurrentField st of
  -- ... existing 0-6 ...
  7 -> st { absRating = filterRating (f (absRating st)) }
  8 -> st  -- Comments edited externally, no direct input
  9 -> st  -- Custom fields have special handling
  _ -> st

-- Helper to filter rating input
filterRating :: Text -> Text
filterRating t = T.filter (`elem` ("12345" :: String)) t
```

**Render changes for new fields:**
```haskell
-- Rating field
, renderField 7 "Rating" (absRating st <> "/5") (absCurrentField st)

-- Comments field (truncated preview)
, renderCommentsField 8 (absComments st) (absCurrentField st)

-- Custom fields
, renderCustomFieldsSection (absCustomFields st) (absCustomFieldIdx st)
    (absCurrentField st == 9) (absEditingCustom st)
```

#### 2. `src/Libri/TUI/App.hs`

**Add imports:**
```haskell
import Brick.Main (suspendAndResume)
import System.Environment (lookupEnv)
import System.Process (callProcess)
import System.IO (hPutStr, hClose, hFlush)
import System.IO.Temp (withSystemTempFile)
```

**Handle Ctrl+E for comments:**
```haskell
VtyEvent (V.EvKey (V.KChar 'e') [V.MCtrl]) ->
  when (absCurrentField abs' == 8) $ do  -- Comments field
    newState <- suspendAndResume $ do
      editor <- fromMaybe "vim" <$> lookupEnv "EDITOR"
      withSystemTempFile "libri-comment.txt" $ \path handle -> do
        T.hPutStr handle (absComments abs')
        hFlush handle
        hClose handle
        callProcess editor [path]
        newComments <- T.pack <$> readFile path
        pure $ st { tuiAddBookState = Just $ abs' { absComments = newComments } }
    put newState
```

**Handle custom field management (when field 9 is selected):**
```haskell
-- Enter custom field editing mode
VtyEvent (V.EvKey V.KEnter []) | absCurrentField abs' == 9 ->
  put $ st { tuiAddBookState = Just $ abs' { absEditingCustom = True } }

-- When in custom field editing mode:
-- j/k to navigate, 'a' to add, 'd' to delete, Enter to edit value, Esc to exit
```

**Update book creation to include new fields:**
```haskell
let book = Book
      { -- ... existing fields ...
      , _rating = parseRating (absRating abs')
      , _comments = if T.null (absComments abs') then Nothing else Just (absComments abs')
      , _custom = Map.fromList $ map (fmap String) (absCustomFields abs')
      -- ...
      }

parseRating :: Text -> Maybe Int
parseRating t = case T.unpack t of
  [c] | c `elem` ("12345" :: String) -> Just (read [c])
  _ -> Nothing
```

### Package Dependencies

Add to `libri.cabal` build-depends:
```
, temporary >= 1.3 && < 2
, process >= 1.6 && < 2
```

---

## UI Mockup

### Add/Edit Form (Extended)
```
┌─ Add New Book ────────────────────────────┐
│                                           │
│       ISBN: 9780134685991▋                │
│      Title: Effective Java                │
│    Authors: Joshua Bloch                  │
│  Publisher: Addison-Wesley                │
│  Published: 2018                          │
│   Location: Office Shelf A                │
│       Tags: programming, java             │
│     Rating: 5/5                           │
│   Comments: Great book on... [Ctrl+E]     │
│    Custom: [Enter to manage]              │
│                                           │
│ [Tab] Next  [Enter] Save  [Esc] Cancel    │
└───────────────────────────────────────────┘
```

### Custom Fields View (when Enter pressed on Custom field)
```
┌─ Custom Fields ───────────────────────────┐
│                                           │
│  > pages: 416                             │
│    condition: like-new                    │
│    edition: 3rd                           │
│                                           │
│  [j/k] Navigate  [a] Add  [d] Delete      │
│  [Enter] Edit value  [Esc] Back           │
└───────────────────────────────────────────┘
```

---

## Acceptance Criteria

- [ ] Rating field accepts only 1-5, ignores other input
- [ ] Comments shows truncated preview with edit hint
- [ ] Ctrl+E opens $EDITOR (or vim) with current comments
- [ ] Edited comments are captured when editor closes
- [ ] Custom fields can be listed, navigated (j/k)
- [ ] Can add new custom field (key then value prompts)
- [ ] Can edit existing custom field value
- [ ] Can delete custom field
- [ ] Existing book data is preserved when editing
- [ ] All three new fields are saved correctly to YAML

---

## Implementation Checklist

- [ ] Add new fields to AddBookState in AddBook.hs
- [ ] Update initAddBookState with empty defaults
- [ ] Update initEditBookState to load existing values
- [ ] Add renderCommentsField helper function
- [ ] Add renderCustomFieldsSection helper function
- [ ] Update renderAddBook/renderEditBook with new fields
- [ ] Update updateCurrentField for fields 7-9
- [ ] Change field modulo from 7 to 10
- [ ] Add filterRating helper
- [ ] Add parseRating helper in App.hs
- [ ] Add Ctrl+E handler for external editor
- [ ] Implement suspendAndResume for editor
- [ ] Add custom field mode handlers (Enter, j, k, a, d, Esc)
- [ ] Update book creation with rating, comments, custom
- [ ] Add temporary and process to cabal dependencies
- [ ] Test with existing books that have these fields
- [ ] Test adding new book with all fields

---

## References

- **Brick suspendAndResume:** [Brick.Main Documentation](https://hackage.haskell.org/package/brick/docs/Brick-Main.html)
- **Current Form Pattern:** `src/Libri/TUI/Views/AddBook.hs:118-127`
- **Book Type:** `src/Libri/Types.hs:74-92`
