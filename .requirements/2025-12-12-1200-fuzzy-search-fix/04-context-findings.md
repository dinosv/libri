# Codebase Analysis Findings

## Architecture Overview

The fuzzy search system is in `src/Libri/Search/Fuzzy.hs`:
- Uses `text-metrics` library for Levenshtein distance (already optimized)
- Tokenizes query and fields, then calculates weighted similarity scores
- Weights: title=3.0, author=2.0, tags=1.5

## Root Cause Analysis

### Problem 1: Config threshold NOT USED

```haskell
-- In Types.hs:243
_fuzzyThreshold = 0.6  -- Config value

-- In Fuzzy.hs:29-30
defaultThreshold :: Double
defaultThreshold = 0.1  -- ALWAYS used, config IGNORED!

-- In Fuzzy.hs:33-35
searchBooks :: Text -> [Book] -> [Book]
searchBooks query books =
  map srBook $ searchBooksWithScore defaultThreshold query books  -- Uses 0.1!
```

**The config's `fuzzyThreshold` (0.6) is never passed to searchBooks!**

### Problem 2: Threshold too low (0.1)

With weights of 3.0/2.0/1.5, even a 10% match on one field exceeds the 0.1 threshold:
- Title match of 0.04 → 0.04 * 3.0 = 0.12 > 0.1 ✓ (passes!)
- This allows almost any partial match through

### Problem 3: Token match threshold too low (0.5)

```haskell
minTokenMatchThreshold :: Double
minTokenMatchThreshold = 0.5  -- 50% similarity counts as match
```

For "baudolino" (9 chars), a word with 5 matching chars could score 0.5+.

### Problem 4: No minimum query length

Short queries like "go" or "a" trigger full fuzzy matching on all books.

### Problem 5: ANY word matching, not ALL

```haskell
-- Current: sum of all matches (ANY word can contribute)
totalScore = titleScore + authorScore + tagScore
```

For "machine learning", if only "machine" matches, book still gets high score.

## Files to Modify

| File | Change |
|------|--------|
| `src/Libri/Search/Fuzzy.hs` | Main fixes: thresholds, min length, all-words matching |
| `src/Libri/TUI/App.hs:131` | Pass config threshold to searchBooks |
| `src/Libri/CLI/Commands.hs:274` | Pass config threshold to searchBooks |

## Best Practices (from research)

- **Threshold 80%+** recommended for name matching to avoid false positives
- **Minimum query length 3** prevents noise from short queries
- For strict matching, require **all query terms to match**
- Levenshtein formula: `1.0 - (distance / maxLength)` (already used correctly)

Sources:
- [Fuzzy Matching Best Practices - Redis](https://redis.io/blog/what-is-fuzzy-matching/)
- [Levenshtein Fuzzy Matching - Medium](https://medium.com/analytics-vidhya/fuzzy-matching-in-python-2def168dee4a)

## Previous Work

A previous requirement (`.requirements/2025-12-12-scroll-sort-search/`) identified these issues but:
- Sort/scroll features were implemented
- Search fixes were planned but threshold issue remains unfixed
