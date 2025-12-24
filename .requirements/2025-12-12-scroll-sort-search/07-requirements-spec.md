# Scrolling, Sorting, and Search Improvements

**Created:** 2025-12-12
**Status:** draft
**Last Updated:** 2025-12-12

---

## Overview

This requirement adds three major improvements to the libri TUI:

1. **Scrolling:** Add proper Brick viewport with scroll bar indicator to the book list, enabling both line-by-line and page-by-page navigation with visual feedback of scroll position.

2. **Sorting:** Add runtime sorting by title, author, or publication date with two-key shortcuts (`st`/`sa`/`sd`), toggle direction on repeat press, and display current sort in the status bar.

3. **Search Fix:** Fix the broken search by applying the configured `fuzzyThreshold` (0.6) which is currently ignored, and replace the inefficient custom Levenshtein implementation with the optimized `text-metrics` library already in dependencies.

---

## Implementation Strategy

### Recommended Skill
**Skill:** `developer`

**Rationale:**
This requirement involves code implementation with multiple file modifications:
- Files to modify: 5 Haskell source files
- Task type: Feature enhancement + bugfix
- Context: TUI improvements requiring Brick knowledge

**To implement:** Run `/implement scroll-sort-search`

---

## Requirements

### Functional Requirements

1. **Scrolling**
   - Book list must be wrapped in a Brick viewport with vertical scrolling
   - Display right-side scroll bar showing current position
   - Support line-by-line (j/k/arrows) and page (PageUp/PageDown) navigation
   - Auto-scroll to keep selected item visible

2. **Sorting**
   - Sort by title (default), author, or publication date
   - Keyboard shortcuts: `st` (title), `sa` (author), `sd` (date published)
   - Toggle ascending/descending on repeat press of same shortcut
   - Display current sort field and direction in footer/status bar
   - Default to title (A-Z) on startup

3. **Search**
   - Apply `fuzzyThreshold` from config (0.6) as minimum match score
   - Search must cover: title, authors, tags (as specified by user)
   - Use optimized `text-metrics` Levenshtein instead of custom implementation
   - Fix: results should not include low-relevance matches

### User Interactions

- **Scrolling:** j/k/Up/Down move selection, PageUp/PageDown scroll pages, scroll bar shows position
- **Sorting:** Press `st` for title sort, `sa` for author, `sd` for date; press again to reverse
- **Search:** `/` to search, results filtered by threshold, sorted by relevance

---

## Technical Implementation

### Architecture Decision
- Add `SortField` and `SortOrder` types to `Types.hs`
- Add sort state fields to `AppState`
- Wrap book list in Brick `viewport` with `withVScrollBars`
- Pass `Config` to search functions to access threshold
- Replace custom Levenshtein with `Data.Text.Metrics.levenshtein`

### Files to Modify

1. **`src/Libri/Types.hs`**
   - Add `SortField` data type: `SortByTitle | SortByAuthor | SortByDate`
   - Add `SortOrder` data type: `Ascending | Descending`
   - Add to `AppState`: `_sortField :: SortField`, `_sortOrder :: SortOrder`
   - Generate lenses for new fields

2. **`src/Libri/TUI/Widgets/Common.hs`**
   - Add `BookListViewport` constructor to `Name` type

3. **`src/Libri/TUI/Views/BookList.hs`**
   - Import `Brick.Widgets.Core (viewport, withVScrollBars, visible)`
   - Wrap `renderBooks` in `viewport BookListViewport Vertical`
   - Add `withVScrollBars OnRight`
   - Use `visible` on selected row for auto-scroll

4. **`src/Libri/TUI/App.hs`**
   - Add sort state to initial state (default: `SortByTitle`, `Ascending`)
   - Add keyboard handlers for `st`, `sa`, `sd` (needs pending key state)
   - Update `getVisibleBooks` to apply sort before search
   - Update footer to show sort shortcuts and current sort
   - Pass config to search for threshold

5. **`src/Libri/Search/Fuzzy.hs`**
   - Change `searchBooksWithScore` signature to accept threshold parameter
   - Replace `filter (\sr -> srScore sr > 0)` with `filter (\sr -> srScore sr >= threshold)`
   - Import `Data.Text.Metrics (levenshtein)`
   - Replace `levenshteinDistance` with `levenshtein` from text-metrics
   - Update `scoreBook` to only search title, authors, tags (remove publisher, comments, series)

### Technology Stack
- Brick 2.x viewport and scroll bar widgets
- `text-metrics` library (already in dependencies)
- Existing lens-based state management

### Integration Points
- Sort state integrates with existing `AppState`
- Viewport integrates with existing `renderBookList`
- Search threshold uses existing `Config._fuzzyThreshold`

---

## Implementation Guide

### Patterns to Follow

```haskell
-- From Brick documentation - viewport with scroll bars
viewport BookListViewport Vertical $
  withVScrollBars OnRight $
    vBox $ zipWith (renderBookRow selectedIdx) [0..] books

-- Auto-scroll to selected item
renderBookRow selectedIdx idx book =
  let widget = ... -- existing row widget
  in if idx == selectedIdx
     then visible widget
     else widget
```

```haskell
-- Sort state in AppState (Types.hs)
data SortField = SortByTitle | SortByAuthor | SortByDate
  deriving (Show, Eq)

data SortOrder = Ascending | Descending
  deriving (Show, Eq)

data AppState = AppState
  { ...
  , _sortField :: SortField
  , _sortOrder :: SortOrder
  }
```

```haskell
-- Two-key sequence handling (App.hs)
-- Option: Use a pending key state
data TUIState = TUIState
  { ...
  , tuiPendingKey :: Maybe Char  -- For two-key sequences like 'st'
  }

-- In handleListViewEvent:
VtyEvent (V.EvKey (V.KChar 's') []) ->
  put $ st { tuiPendingKey = Just 's' }

VtyEvent (V.EvKey (V.KChar 't') []) | tuiPendingKey st == Just 's' ->
  -- Toggle title sort
  let newOrder = if appSt ^. sortField == SortByTitle && appSt ^. sortOrder == Ascending
                 then Descending else Ascending
  in put $ st { tuiAppState = appSt & sortField .~ SortByTitle & sortOrder .~ newOrder
              , tuiPendingKey = Nothing }
```

```haskell
-- Apply sort in getVisibleBooks (App.hs)
getVisibleBooks :: AppState -> [Book]
getVisibleBooks st =
  let sorted = applySortOrder (st ^. sortField) (st ^. sortOrder) (st ^. books)
      query = st ^. searchQuery
  in if T.null query
     then sorted
     else searchBooks (st ^. config . fuzzyThreshold) query sorted

applySortOrder :: SortField -> SortOrder -> [Book] -> [Book]
applySortOrder field order books =
  let cmp = case field of
        SortByTitle  -> comparing (^. title)
        SortByAuthor -> comparing (maybe "" head' . nonEmpty . (^. authors))
        SortByDate   -> comparing (^. published)
      sorted = sortBy cmp books
  in case order of
       Ascending  -> sorted
       Descending -> reverse sorted
```

```haskell
-- Fix search threshold (Fuzzy.hs)
searchBooksWithScore :: Double -> Text -> [Book] -> [SearchResult]
searchBooksWithScore threshold query books
  | T.null (T.strip query) = map (\b -> SearchResult b 1.0) books
  | otherwise =
      let queryTokens = tokenize query
          results = map (scoreBook queryTokens) books
          filtered = filter (\sr -> srScore sr >= threshold) results  -- USE THRESHOLD
      in sortBy (comparing (Down . srScore)) filtered

-- Use text-metrics instead of custom
import qualified Data.Text.Metrics as TM

levenshteinSimilarity :: Text -> Text -> Double
levenshteinSimilarity s1 s2 =
  let dist = TM.levenshtein s1 s2
      maxLen = max (T.length s1) (T.length s2)
  in if maxLen == 0 then 1.0 else max 0 (1.0 - fromIntegral dist / fromIntegral maxLen)
```

### Step-by-Step Approach

1. **Types.hs:** Add `SortField`, `SortOrder` types and AppState fields
2. **Common.hs:** Add `BookListViewport` to Name
3. **BookList.hs:** Wrap in viewport with scroll bars, add `visible` for selected
4. **App.hs:** Add `tuiPendingKey`, sort handlers, update footer, update `getVisibleBooks`
5. **Fuzzy.hs:** Add threshold parameter, use text-metrics, limit search to title/authors/tags

---

## Testing Strategy

- Test sorting: verify each sort field works, verify toggle direction
- Test scrolling: verify viewport scrolls, scroll bar appears
- Test search: verify threshold filters low-score results, verify performance improved

---

## Edge Cases & Constraints

### Edge Cases
- Empty book list (viewport should handle gracefully)
- Books with no author (sort by author should handle)
- Books with no publication date (sort by date should handle)
- Search query with no matches above threshold

### Technical Constraints
- Brick viewport requires unique Name value
- Two-key sequences need state to track pending key
- Must clear pending key on timeout or other key press

---

## Acceptance Criteria

- [ ] Book list has visible scroll bar on the right
- [ ] Selected item always visible (auto-scroll)
- [ ] `st` sorts by title, toggles direction on repeat
- [ ] `sa` sorts by author, toggles direction on repeat
- [ ] `sd` sorts by date published, toggles direction on repeat
- [ ] Footer shows current sort (e.g., "Title ↑" or "Author ↓")
- [ ] Footer shows sort shortcuts
- [ ] Search filters results below 0.6 threshold
- [ ] Search only matches title, authors, tags
- [ ] Search performance noticeably improved

---

## Implementation Checklist

- [ ] Add `SortField` and `SortOrder` types to `Types.hs`
- [ ] Add `_sortField`, `_sortOrder` fields to `AppState` with lenses
- [ ] Add `BookListViewport` to `Name` in `Common.hs`
- [ ] Wrap book list in `viewport` with `withVScrollBars OnRight` in `BookList.hs`
- [ ] Add `visible` wrapper for selected row in `BookList.hs`
- [ ] Add `tuiPendingKey` to `TUIState` in `App.hs`
- [ ] Add `s` key handler to set pending key in `App.hs`
- [ ] Add `t`/`a`/`d` handlers when pending key is `s` in `App.hs`
- [ ] Add `applySortOrder` function in `App.hs`
- [ ] Update `getVisibleBooks` to apply sort in `App.hs`
- [ ] Update footer to show sort shortcuts and current sort in `App.hs`
- [ ] Update `searchBooksWithScore` to accept threshold in `Fuzzy.hs`
- [ ] Use threshold in filter instead of `> 0` in `Fuzzy.hs`
- [ ] Import and use `Data.Text.Metrics.levenshtein` in `Fuzzy.hs`
- [ ] Remove custom `levenshteinDistance` and `levenshteinList` from `Fuzzy.hs`
- [ ] Update `scoreBook` to only score title, authors, tags in `Fuzzy.hs`
- [ ] Build and test all features

---

## References

- **Codebase Analysis:** `04-context-findings.md`
- **Similar Features:** Brick viewport docs, existing navigation in `BookList.hs`
- **Dependencies:** `text-metrics` (already in libri.cabal line 61)

---

## Notes

- The `text-metrics` package is already a dependency, so no new deps needed
- Two-key sequences (`st`, `sa`, `sd`) require tracking a pending key state
- Consider adding a timeout to clear pending key if user doesn't complete sequence
- Sort direction indicator: ↑ for ascending, ↓ for descending
