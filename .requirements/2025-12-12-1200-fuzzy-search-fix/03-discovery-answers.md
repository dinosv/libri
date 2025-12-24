# Discovery Answers

## Summary

| Question | Answer |
|----------|--------|
| Q1: Problem type | Too loose matching + too many results + poor ranking |
| Q2: Noise source | Title and Author fields |
| Q3: Example | "baudolino" returns unrelated books |
| Q4: Strictness | Strict - typo tolerance only |
| Q5: Multi-word | All words must match |
| Q6: Min length | 3 characters minimum for fuzzy matching |

## Detailed Answers

### Q1: What type of irrelevant results are you seeing?
**Selected:** 1, 2, 3
- Returns books that share only 1-2 letters with the query (too loose matching)
- Returns too many results - everything seems to match
- Results are ranked incorrectly - relevant books appear at the bottom

### Q2: Which fields are producing the noise?
**Selected:** 1, 2
- Title matches that shouldn't match
- Author name false positives

### Q3: Can you give an example of a problematic search?
**Answer:** "baudolino" - searching for this title returns unrelated books

### Q4: What matching behavior would you prefer?
**Selected:** 1 (default)
- Strict - only exact or very close matches (typo tolerance only)

### Q5: Should search require all query words to match?
**Selected:** 1 (default)
- Yes - ALL words must match somewhere in the book

### Q6: What minimum query length should trigger fuzzy matching?
**Selected:** 1 (default)
- Require at least 3 characters for fuzzy matching
