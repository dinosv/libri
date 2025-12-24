# Discovery Questions - Batch ISBN Import

Generated based on analysis of existing codebase:
- Current ISBN lookup: `src/Libri/ISBN/OpenLibrary.hs` - `fetchByISBN`
- CLI commands: `src/Libri/CLI/Commands.hs` - `CmdAdd`, `runAdd`

---

## Q1: File Format
```
What format should the ISBN input file use?

1. One ISBN per line (simple text file) [default - easiest to create/edit]
2. CSV with ISBN column and optional metadata columns
3. JSON array of ISBN strings
4. Other (please specify)
```

## Q2: Invalid ISBN Handling
```
How should the system handle ISBNs that can't be found in OpenLibrary?

1. Skip and continue, report at the end [default - don't block entire batch]
2. Prompt user for each failure (interactive mode)
3. Stop the entire batch on first failure
4. Other (please specify)
```

## Q3: Duplicate Handling
```
What should happen if an ISBN already exists in your collection?

1. Skip duplicates silently [default - safe, no overwrites]
2. Skip duplicates but warn
3. Update existing book with new metadata
4. Other (please specify)
```

## Q4: Rate Limiting
```
OpenLibrary API has rate limits. How should the batch handle this?

1. Add automatic delay between requests (1-2 sec) [default - respectful to API]
2. Process as fast as possible
3. Let user configure the delay
4. Other (please specify)
```

## Q5: Progress Feedback
```
How should progress be reported during batch import?

1. Show progress for each book (verbose) [default - see what's happening]
2. Only show summary at the end
3. Progress bar with minimal output
4. Other (please specify)
```

## Q6: Interface
```
Where should this batch import feature be available?

1. CLI command only (e.g., `libri --import-batch file.txt`) [default - batch ops suit CLI]
2. Both CLI and TUI
3. TUI only (file picker dialog)
4. Other (please specify)
```
