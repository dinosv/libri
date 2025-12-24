# Expert Answers

## Summary

| Question | Answer |
|----------|--------|
| Q1: Overall threshold | Use config value 0.6 (wire it up) |
| Q2: Token threshold | Keep at 0.5 (current) |
| Q3: Multi-word matching | Require MAJORITY (>50%) of words |
| Q4: Minimum query length | 3+ characters for fuzzy |
| Q5: Short query behavior | Exact substring match only |

## Detailed Answers

### Q1: What overall threshold should be used?
**Selected:** 1 (default)
- Use config value 0.6 (60% minimum weighted score)
- Wire up the config's `_fuzzyThreshold` which is currently ignored

### Q2: What token-level similarity threshold?
**Selected:** 3
- Keep at 0.5 (current behavior)

### Q3: How should multi-word queries work?
**Selected:** 2
- Require MAJORITY (>50%) of query words to have a match above threshold

### Q4: Should we add minimum query length?
**Selected:** 1 (default)
- Yes, require 3+ characters for fuzzy matching

### Q5: How should short queries (below minimum) behave?
**Selected:** 1 (default)
- Use exact substring match only (no fuzzy) - still allows precise short searches
