# Discovery Questions

## Q1: What type of irrelevant results are you seeing?

What best describes the problem with the fuzzy search results?

1. Returns books that share only 1-2 letters with the query (too loose matching)
2. Returns too many results - everything seems to match
3. Results are ranked incorrectly - relevant books appear at the bottom
4. Short queries (1-2 chars) return too much noise
5. Other (please specify)

---

## Q2: Which fields are producing the noise?

Where do the irrelevant matches seem to come from?

1. Title matches that shouldn't match [default - most common source of noise]
2. Author name false positives
3. Tag matches that are too loose
4. All fields equally
5. Other (please specify)

---

## Q3: Can you give an example of a problematic search?

What's a typical search that returns bad results?

1. Single word search (e.g., "python") returns unrelated books
2. Author name search returns books by other authors
3. Partial title search matches wrong titles
4. Short queries like "go" or "js" match everything
5. Other (please specify)

---

## Q4: What matching behavior would you prefer?

How strict should the fuzzy matching be?

1. Strict - only exact or very close matches (typo tolerance only) [default - reduces noise]
2. Moderate - allow some flexibility but filter obvious non-matches
3. Loose - keep current behavior but improve ranking
4. Other (please specify)

---

## Q5: Should search require all query words to match?

When searching "machine learning", should both words need to match?

1. Yes - ALL words must match somewhere in the book [default - more precise]
2. No - ANY word matching is enough (current behavior)
3. Configurable by user
4. Other (please specify)

---

## Q6: What minimum query length should trigger fuzzy matching?

For very short queries, should fuzzy matching apply?

1. Require at least 3 characters for fuzzy matching [default - prevents noise from short queries]
2. Require at least 2 characters
3. Any length should work (current behavior)
4. Other (please specify)
