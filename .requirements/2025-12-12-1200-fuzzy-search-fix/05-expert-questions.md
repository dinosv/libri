# Expert Questions

Based on codebase analysis, the following implementation decisions are needed:

## Q1: What overall threshold should be used?

The config has `fuzzyThreshold = 0.6` but it's ignored. What value should we use?

1. Use config value 0.6 (60% minimum weighted score) [default - as originally intended]
2. Increase to 0.7 (stricter)
3. Increase to 0.8 (very strict, typo tolerance only)
4. Other (please specify)

**Why this matters:**
The current `defaultThreshold = 0.1` in Fuzzy.hs:29 is far too low. With weights of 3.0/2.0/1.5, even a 4% title match passes. The config value 0.6 was intended but never wired up.

---

## Q2: What token-level similarity threshold?

Currently `minTokenMatchThreshold = 0.5` means 50% similar tokens count as matches.

1. Increase to 0.7 (70% similarity required) [default - stricter matching]
2. Increase to 0.8 (very strict)
3. Keep at 0.5 (current)
4. Other (please specify)

**Why this matters:**
For "baudolino" (9 chars), a 5-char overlap could pass at 0.5. At 0.7, you'd need 7+ chars to match, filtering more noise.

---

## Q3: How should multi-word queries work?

Currently any word matching contributes to score. Should we require all words?

1. Require ALL query words to have a match above threshold [default - per discovery]
2. Require MAJORITY (>50%) of words to match
3. Keep ANY word matching (current behavior)
4. Other (please specify)

**Why this matters:**
For "machine learning python", current code sums all matches. If only "python" matches a book, it still appears. Requiring ALL words eliminates these false positives.

---

## Q4: Should we add minimum query length?

Short queries like "go" or "a" match almost everything.

1. Yes, require 3+ characters for fuzzy matching [default - per discovery]
2. Yes, require 2+ characters
3. No, allow any length
4. Other (please specify)

**Why this matters:**
Short queries with Levenshtein can match many unrelated words. Requiring 3 chars prevents noise while still allowing reasonable searches.

---

## Q5: How should short queries (below minimum) behave?

If query is too short (e.g., 2 chars with 3-char minimum):

1. Use exact substring match only (no fuzzy) [default - still useful]
2. Return all books (ignore query)
3. Return no results
4. Other (please specify)

**Why this matters:**
Users might still want to search "AI" or "Go". Exact substring matching prevents fuzzy noise while allowing precise short searches.
