# Expert Questions - Batch ISBN Import

Based on codebase analysis findings.

---

## Q7: Review Interface Style
```
Found that CLI commands like `runImportCalibre` save immediately without review.
For the review step you requested, how should the interface work?

1. Show table summary, then prompt y/n/select [default - simple, matches CLI style]
2. Interactive selection with arrow keys (like TUI)
3. Output to temporary file for manual review, then re-run to import
4. Other (please specify)

**Why this matters:**
The existing CLI commands (`runAdd`, `runImportCalibre`) don't have a review step.
Adding one requires deciding on the interaction model.
```

## Q8: Which Books to Show for Review
```
When displaying fetched books for review, what information should be shown?

1. Title and Authors only [default - concise, fits terminal width]
2. Title, Authors, Publisher, Year
3. Full metadata including ISBN, tags, description preview
4. Other (please specify)

**Why this matters:**
Terminal width limits how much we can show per line. More detail = more scrolling.
```

## Q9: Handling Partial Failures
```
If 10 ISBNs are submitted and 3 fail to fetch, what should happen?

1. Show success + failures, let user import successful ones [default - flexible]
2. Require all or nothing (abort if any fail)
3. Automatically retry failed ones once before giving up
4. Other (please specify)

**Why this matters:**
OpenLibrary may not have every ISBN. User likely wants to import what's available.
```

## Q10: Duplicate Confirmation Granularity
```
For duplicates, should the user decide per-duplicate or globally?

1. Global setting: "Skip all duplicates" or "Import all duplicates" [default - simpler]
2. Per-duplicate: "ISBN X exists. Import anyway? [y/n/all/none]"
3. Show duplicates separately, let user select which to import
4. Other (please specify)

**Why this matters:**
With many duplicates, per-item prompts become tedious. But sometimes user wants control.
```

## Q11: Command Name
```
What should the CLI flag be called?

1. --import-batch FILE [default - matches --import-calibre pattern]
2. --import-isbn FILE
3. --batch FILE
4. Other (please specify)

**Why this matters:**
Existing pattern: `--import-calibre`. Consistency helps discoverability.
```
