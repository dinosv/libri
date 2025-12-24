# Codebase Analysis Findings

## Architecture Overview

- **Language:** Haskell with GHC2021
- **TUI Framework:** Brick 2.x with VTY
- **State Management:** Lens-based (microlens)
- **Storage:** YAML files (one per book)

## Current Form Structure

### AddBookState (src/Libri/TUI/Views/AddBook.hs:24-36)
```haskell
data AddBookState = AddBookState
  { absIsbn :: Text
  , absTitle :: Text
  , absAuthors :: Text      -- Comma-separated
  , absPublisher :: Text
  , absPublished :: Text    -- Year (e.g., "2024")
  , absLocation :: Text
  , absTags :: Text         -- Comma-separated
  , absCurrentField :: Int  -- Which field is selected (0-6)
  , absIsEdit :: Bool
  , absOriginalId :: Maybe BookId
  }
```

### Book Type Fields to Support (src/Libri/Types.hs:85-88)
```haskell
  , _rating :: Maybe Int      -- 1-5 rating
  , _comments :: Maybe Text   -- Free-form text
  , _custom :: Map Text Value -- Key-value pairs (Aeson Value)
```

## Files to Modify

1. **`src/Libri/TUI/Views/AddBook.hs`**
   - Add `absRating :: Text` field (stores "1"-"5" or "")
   - Add `absComments :: Text` field (display only, edited externally)
   - Add `absCustomFields :: [(Text, Text)]` field (list of key-value pairs)
   - Add `absCustomFieldIdx :: Int` field (for custom field navigation)
   - Add `absEditingCustom :: Bool` field (whether in custom field edit mode)
   - Update `initAddBookState` and `initEditBookState`
   - Update `renderAddBook` and `renderEditBook` to show new fields
   - Update `updateCurrentField` to handle fields 7-9
   - Change field count from 7 to 10

2. **`src/Libri/TUI/App.hs`**
   - Update book creation in `handleAddEditEvent` to include rating, comments, custom
   - Add handler for Ctrl+E to open external editor for comments
   - Add handler for custom field management (when on custom field)
   - Import `System.Process` and use Brick's `suspendAndResume`

3. **`src/Libri/TUI/Widgets/Common.hs`** (optional)
   - May need helper for rendering star rating

## External Editor Implementation

Brick provides `suspendAndResume` for calling external programs:

```haskell
import Brick.Main (suspendAndResume)
import System.Environment (lookupEnv)
import System.Process (callProcess)
import System.IO.Temp (withSystemTempFile)

-- When user presses Ctrl+E on comments field:
VtyEvent (V.EvKey (V.KChar 'e') [V.MCtrl]) ->
  when (absCurrentField abs' == commentsFieldIdx) $ do
    suspendAndResume $ do
      editor <- fromMaybe "vi" <$> lookupEnv "EDITOR"
      withSystemTempFile "libri-comment.txt" $ \path handle -> do
        hPutStr handle (T.unpack $ absComments abs')
        hClose handle
        callProcess editor [path]
        newComments <- T.pack <$> readFile path
        pure $ st { tuiAddBookState = Just $ abs' { absComments = newComments } }
```

## Custom Fields UI Design

Since user wants vim-like navigation for custom fields:

```
Custom Fields:
  > genre: fiction     (selected, press Enter to edit, 'd' to delete)
    pages: 342
    condition: good
  [a] Add new field

Navigation: j/k to move, Enter to edit, 'd' to delete, 'a' to add, Esc to exit
```

## Field Layout (Extended Form)

```
Field 0: ISBN
Field 1: Title
Field 2: Authors (comma-separated)
Field 3: Publisher
Field 4: Published (year)
Field 5: Location
Field 6: Tags (comma-separated)
Field 7: Rating (1-5)
Field 8: Comments [Ctrl+E to edit]
Field 9: Custom Fields [Enter to manage]
```

## Patterns to Follow

### From renderField (AddBook.hs:118-127)
```haskell
renderField :: Int -> Text -> Text -> Int -> Widget Name
renderField idx label value currentIdx =
  let isSelected = idx == currentIdx
      labelWidget = withAttr labelAttr $ txt $ label <> ": "
      cursor = if isSelected then "▋" else ""
      valueAttr' = if isSelected then selectedAttr else valueAttr
  in hBox
       [ padRight (Pad 1) $ hLimit 12 $ padLeft Max labelWidget
       , withAttr valueAttr' $ txtWrap $ value <> cursor
       ]
```

### From updateCurrentField (AddBook.hs:183-193)
```haskell
updateCurrentField :: (Text -> Text) -> AddBookState -> AddBookState
updateCurrentField f st = case absCurrentField st of
  0 -> st { absIsbn = f (absIsbn st) }
  -- ... pattern to extend
```

## Dependencies Needed

```haskell
-- Already available
import qualified Data.Map.Strict as Map
import Data.Aeson (Value(..))

-- Need to add
import System.Environment (lookupEnv)
import System.Process (callProcess)
import System.IO (hPutStr, hClose)
import System.IO.Temp (withSystemTempFile)  -- from 'temporary' package
```

## Package Dependencies

May need to add to `libri.cabal`:
```
, temporary >= 1.3 && < 2
, process >= 1.6 && < 2
```

## Testing Considerations

- Rating should validate 1-5 range
- Comments can be empty
- Custom fields should handle empty key/value gracefully
- External editor should work with $EDITOR unset (fallback to vi/nano)
