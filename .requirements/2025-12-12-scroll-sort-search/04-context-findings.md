# Codebase Analysis Findings

## Architecture Overview

- **Tech Stack:** Haskell with GHC 9.6.6, Brick TUI framework 2.x, microlens for state management
- **State Management:** `TUIState` wraps `AppState` which contains `books`, `selectedIndex`, `searchQuery`, `currentView`
- **Rendering:** Main layout in `App.hs:mainLayout`, book list in `BookList.hs:renderBookList`
- **Search:** Fuzzy search in `Fuzzy.hs` using Levenshtein distance

## Current Implementation Analysis

### Scrolling (Current State)
- **Location:** `src/Libri/TUI/Views/BookList.hs:35-37` and `App.hs:246-260`
- **Problem:** No viewport wrapper - renders ALL books with `vBox $ zipWith renderBookRow`
- **Navigation:** j/k/Up/Down moves `selectedIndex`, PageUp/PageDown moves by 10
- **Missing:** No visual scroll indicator, no Brick viewport used

```haskell
-- BookList.hs:35-37 - No viewport!
renderBooks :: [Book] -> Int -> Widget Name
renderBooks books selectedIdx =
  vBox $ zipWith (renderBookRow selectedIdx) [0..] books
```

### Sorting (Current State)
- **Location:** `src/Libri/TUI/App.hs:63`
- **Implementation:** Only sorts by title at load time: `sortBy (comparing (^. title)) books'`
- **Problem:** No runtime sorting, hardcoded to title only, no sort order state
- **Missing:** No `SortField` or `SortOrder` in `AppState`, no keyboard shortcuts

```haskell
-- App.hs:63 - Hardcoded title sort
sortedBooks = sortBy (comparing (^. title)) books'
```

### Search (Current State)
- **Location:** `src/Libri/Search/Fuzzy.hs`
- **Algorithm:** Levenshtein distance with tokenization
- **Scoring:** Title (3.0), Authors (2.0), Tags (1.5), Series (1.5), Publisher (1.0), Comments (0.5), ISBN (2.0 exact)
- **Filtering:** `filter (\sr -> srScore sr > 0)` - threshold is 0, not using `fuzzyThreshold` from config!

**Problems Identified:**
1. **Threshold not used:** `fuzzyThreshold` in Config (0.6) is NEVER applied - any score > 0 matches
2. **Levenshtein is O(n*m):** The `levenshteinList` uses `!!` indexing - O(n) per access making it O(n²*m²)
3. **No short-circuit:** Computes full distance even for obvious non-matches

```haskell
-- Fuzzy.hs:36-37 - Threshold should be fuzzyThreshold, not 0
filtered = filter (\sr -> srScore sr > 0) results  -- BUG: Should use fuzzyThreshold!

-- Fuzzy.hs:102-114 - Inefficient Levenshtein
levenshteinList :: Eq a => [a] -> [a] -> Int
levenshteinList xs ys = table !! length xs !! length ys  -- O(n) access!
```

## Files to Modify

1. **`src/Libri/Types.hs`**
   - Add `SortField` type (Title, Author, Published)
   - Add `SortOrder` type (Ascending, Descending)
   - Add `_sortField` and `_sortOrder` to `AppState`

2. **`src/Libri/TUI/Views/BookList.hs`**
   - Wrap book list in `viewport` with `Vertical` orientation
   - Add scroll position indicator
   - Use `withVScrollBars` for visual feedback

3. **`src/Libri/TUI/App.hs`**
   - Add sort keyboard handlers (st/sa/sd)
   - Add sort indicator to footer
   - Update `getVisibleBooks` to apply current sort
   - Pass `Config` to search for threshold

4. **`src/Libri/Search/Fuzzy.hs`**
   - Use `fuzzyThreshold` from Config
   - Optimize Levenshtein with Vector or early termination
   - Add minimum score filtering

5. **`src/Libri/TUI/Widgets/Common.hs`**
   - Add `Name` constructor for viewport: `BookListViewport`

## Brick Viewport Pattern

From Brick documentation:
```haskell
-- Wrap content in viewport with scroll bars
viewport BookListViewport Vertical $
  withVScrollBars OnRight $
    vBox $ zipWith renderBookRow ...

-- In event handler, use viewportScroll
let vp = viewportScroll BookListViewport
vScrollBy vp 1        -- scroll by 1 row
vScrollPage vp Down   -- page down
```

## Similar Patterns in Codebase

The `MoveBook.hs` view uses a similar list pattern but also lacks viewport:
```haskell
-- MoveBook.hs - same pattern, no viewport
renderLocationList :: [Text] -> Int -> Widget Name
renderLocationList locs selectedIdx =
  vBox $ zipWith (renderLocationRow selectedIdx) [0..] locs
```

## Recommended Approach

### 1. Scrolling
- Add `BookListViewport` to `Name` type in `Common.hs`
- Wrap `renderBooks` output in `viewport BookListViewport Vertical`
- Add `withVScrollBars OnRight` for scroll indicator
- Use `visible` on selected row to auto-scroll

### 2. Sorting
- Add to `AppState`: `_sortField :: SortField`, `_sortOrder :: SortOrder`
- Keyboard shortcuts: `st` (title), `sa` (author), `sd` (date)
- Toggle direction on repeat press
- Apply sort in `getVisibleBooks` before search
- Show current sort in footer

### 3. Search Fix
- Pass `Config` to `searchBooksWithScore`
- Use `_fuzzyThreshold` for minimum score
- Replace list-based Levenshtein with Vector-based or use `text-metrics` library (already in deps!)
- The `text-metrics` package has optimized `levenshtein` and `damerauLevenshtein`

## Technical Constraints

1. **text-metrics already in deps** - Use it instead of custom Levenshtein!
2. Brick viewports require unique `Name` values
3. Sort state must persist across book reload operations
4. Search should apply AFTER sort for consistent ordering
