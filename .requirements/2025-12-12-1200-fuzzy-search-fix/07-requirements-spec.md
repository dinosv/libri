# Fuzzy Search Fix - Reduce Irrelevant Results

**Created:** 2025-12-12
**Status:** draft
**Last Updated:** 2025-12-12

---

## Overview

The fuzzy search returns too many irrelevant results because:
1. The config's `fuzzyThreshold` (0.6) is **ignored** - code uses hardcoded 0.1
2. No minimum query length - short queries match everything
3. ANY word matching counts - should require majority of query words

This fix will:
- Wire up the config threshold (0.6) properly
- Add 3-character minimum for fuzzy matching
- Require >50% of query words to match
- Fall back to exact substring matching for short queries

---

## Implementation Strategy

### Recommended Skill
**Skill:** `developer`

**Rationale:**
- Files to modify: 3 Haskell source files
- Task type: Bugfix with algorithm changes
- Context: Search algorithm refinement

**To implement:** Run `/implement fuzzy-search-fix`

---

## Requirements

### Functional Requirements

1. **Use config threshold**: Apply `_fuzzyThreshold` from Config (0.6) instead of hardcoded 0.1
2. **Minimum query length**: Require 3+ characters for fuzzy matching
3. **Short query fallback**: Queries < 3 chars use exact substring match (case-insensitive)
4. **Majority word matching**: For multi-word queries, >50% of words must match above threshold
5. **Keep token threshold at 0.5**: Individual token similarity threshold unchanged

### Expected Behavior

| Query | Behavior |
|-------|----------|
| "baudolino" | Fuzzy match, requires 60% weighted score |
| "machine learning" | Both words must have matches (2/2 = 100% > 50%) |
| "go" | Exact substring only (< 3 chars) |
| "AI" | Exact substring only (< 3 chars) |

---

## Technical Implementation

### Files to Modify

#### 1. `src/Libri/Search/Fuzzy.hs`

**Changes:**
- Remove `defaultThreshold` constant
- Add `minQueryLength = 3` constant
- Modify `searchBooks` to accept threshold parameter
- Add `searchBooksExact` for short query fallback
- Modify `scoreBook` to track word match count
- Add majority-word filtering logic

**New signature:**
```haskell
searchBooks :: Double -> Text -> [Book] -> [Book]
searchBooks threshold query books = ...
```

**Add exact substring search:**
```haskell
searchBooksExact :: Text -> [Book] -> [Book]
searchBooksExact query books =
  let q = T.toLower query
  in filter (bookContains q) books

bookContains :: Text -> Book -> Bool
bookContains q book =
  q `T.isInfixOf` T.toLower (book ^. title)
  || any (T.isInfixOf q . T.toLower) (book ^. authors)
  || any (T.isInfixOf q . T.toLower) (book ^. tags)
```

**Add majority-word logic:**
```haskell
-- Check if majority of query tokens have matches
hasMajorityMatches :: [Text] -> Book -> Bool
hasMajorityMatches queryTokens book =
  let matchCount = countMatchingTokens queryTokens book
      required = (length queryTokens + 1) `div` 2  -- >50%
  in matchCount >= required
```

#### 2. `src/Libri/TUI/App.hs`

**Line 131 - Change:**
```haskell
-- Before:
else searchBooks query sorted

-- After:
else let threshold = st ^. config . fuzzyThreshold
     in searchBooks threshold query sorted
```

**May need to import:**
```haskell
import Libri.Types (fuzzyThreshold)
```

#### 3. `src/Libri/CLI/Commands.hs`

**Line 274 - Change:**
```haskell
-- Before:
let results = searchBooks query books

-- After:
let threshold = _fuzzyThreshold cfg
    results = searchBooks threshold query books
```

---

## Algorithm Changes

### Current Flow (broken):
```
query → tokenize → score all books → filter by 0.1 → sort by score
```

### New Flow (fixed):
```
query → check length
  ├─ < 3 chars → exact substring search
  └─ >= 3 chars → tokenize → score all books
                  → filter by majority-word match
                  → filter by 0.6 threshold
                  → sort by score
```

---

## Testing Strategy

Update `test/SearchSpec.hs`:

```haskell
describe "threshold filtering" $ do
  it "filters low-relevance matches with 0.6 threshold" $ do
    let results = searchBooksWithScore 0.6 "baudolino" testBooks
    -- Should only match books with high relevance

  it "uses exact match for short queries" $ do
    let results = searchBooks 0.6 "go" testBooksWithGo
    -- Should only find exact substring matches

describe "majority word matching" $ do
  it "requires majority of query words to match" $ do
    let results = searchBooks 0.6 "machine learning" testBooks
    -- Should not match books with only "machine" or only "learning"
```

---

## Acceptance Criteria

- [ ] Searching "baudolino" only returns the Umberto Eco novel (not unrelated books)
- [ ] Short queries (< 3 chars) use exact substring match
- [ ] Multi-word queries require >50% of words to match
- [ ] Config's `fuzzyThreshold` (0.6) is used, not hardcoded 0.1
- [ ] Tests pass for new threshold behavior
- [ ] Build succeeds with no new warnings

---

## Implementation Checklist

- [ ] Modify `Fuzzy.hs`: Remove `defaultThreshold`, add threshold parameter
- [ ] Modify `Fuzzy.hs`: Add `minQueryLength = 3` constant
- [ ] Modify `Fuzzy.hs`: Add `searchBooksExact` for short queries
- [ ] Modify `Fuzzy.hs`: Add majority-word matching logic
- [ ] Modify `Fuzzy.hs`: Update `searchBooks` to handle short queries
- [ ] Modify `TUI/App.hs:131`: Pass config threshold to searchBooks
- [ ] Modify `CLI/Commands.hs:274`: Pass config threshold to searchBooks
- [ ] Update `SearchSpec.hs`: Add tests for new behavior
- [ ] Run `cabal build` - verify no errors
- [ ] Run `cabal test` - verify all tests pass
- [ ] Manual test: search "baudolino" returns only relevant results

---

## References

- **Codebase Analysis:** `04-context-findings.md`
- **Similar Features:** Previous requirement at `.requirements/2025-12-12-scroll-sort-search/`
- **Best Practices:**
  - [Fuzzy Matching - Redis](https://redis.io/blog/what-is-fuzzy-matching/)
  - [Levenshtein Fuzzy Matching](https://medium.com/analytics-vidhya/fuzzy-matching-in-python-2def168dee4a)

---

## Notes

- The `text-metrics` library is already used for Levenshtein - no changes needed there
- Token-level threshold stays at 0.5 as requested
- The 0.6 overall threshold affects the weighted sum of all field scores
