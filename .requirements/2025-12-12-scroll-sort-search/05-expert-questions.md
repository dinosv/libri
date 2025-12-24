# Expert Questions

## Q7: Viewport Scroll Bar Style
How should the scroll indicator appear?

1. Right-side scroll bar with handle (Brick built-in) [default - minimal code change]
2. Footer indicator showing "X/Y books" position
3. Both scroll bar and footer indicator
4. Other (please specify)

**Why this matters:**
Brick has built-in `withVScrollBars OnRight` that works out of the box. A custom footer indicator requires tracking visible range manually.

## Q8: Sort Keyboard Shortcuts
Which keyboard shortcuts should trigger sorting?

1. `st` (title), `sa` (author), `sd` (date) - two-key sequences [default - memorable, consistent]
2. `1` (title), `2` (author), `3` (date) - single key
3. `s` opens sort popup menu with options
4. Other (please specify)

**Why this matters:**
The footer already shows shortcuts like `("/", "Search")`. Two-key sequences like `st` avoid conflicting with existing single-key bindings (`s` is not used, but `d` is delete).

## Q9: Search Threshold Behavior
The config has `fuzzyThreshold: 0.6` but it's never used. How should we apply it?

1. Use threshold as minimum score (filter out < 0.6) [default - fixes current bug]
2. Use threshold for fuzzy matching only, exact matches always pass
3. Make threshold adjustable with a keyboard shortcut
4. Other (please specify)

**Why this matters:**
Found at `Fuzzy.hs:36` - results filter `srScore > 0` but should use `> fuzzyThreshold`. This is likely causing irrelevant results.

## Q10: Search Performance Fix
The custom Levenshtein is O(n²). The `text-metrics` package is already in dependencies. Should we use it?

1. Yes, use `text-metrics` Levenshtein (already in deps, optimized) [default - zero new deps]
2. Keep custom implementation but optimize with Vector
3. Switch to simpler substring matching for speed
4. Other (please specify)

**Why this matters:**
`text-metrics` at line 61 in cabal file already provides `Data.Text.Metrics.levenshtein`. The custom implementation at `Fuzzy.hs:101-114` uses `!!` list indexing which is O(n) per access.

## Q11: Sort Persistence
Should sort preference persist between sessions?

1. No, always start with title sort [default - simpler, current behavior]
2. Yes, save to config file
3. Remember during session only (reset on restart)
4. Other (please specify)

**Why this matters:**
Adding persistence requires modifying Config and the YAML save/load logic. Session-only is simpler but less convenient.
