# Data Enrichment

Date: 2026-04-25
Status: Approved

## Problem

After Calibre re-import, 168/449 books are missing tags and 72/449 are missing
comments/descriptions. 443 books have ISBNs that can be used to look up metadata
from OpenLibrary.

## Solution

A CLI command `libri --enrich` that batch-fetches missing tags and descriptions
from OpenLibrary by ISBN, merging results into existing book data.

## Design

### Command

`libri --enrich` scans all books, identifies those missing tags or comments with
a valid ISBN, looks up each on OpenLibrary, and merges results. Progress is printed
per book.

Output format:

```
Enriching 172 books with missing data...

  1/172: Rebano (9789563605099)... +5 tags, +description
  2/172: Mitologias del mediterraneo al Ganges (9788424928858)... +3 tags
  3/172: El tercer testamento (9788499471655)... not found
  ...

Enrichment complete!
  142 books updated
  18 books not found on OpenLibrary
  12 books already complete (skipped)
```

Books that already have both tags AND comments are skipped (no API call). Books
without an ISBN are skipped. Rate limiting: 1 second delay between requests,
reusing a single HTTP manager.

### What Gets Enriched

OpenLibrary ISBN endpoint returns `subjects` and `description`.

Mapping to libri fields:

- `subjects` -> `_tags`: merged with existing tags. Deduplication is
  case-insensitive using `normalizeText`. OpenLibrary subjects taken as-is.
  Capped at 10 new tags per book to avoid noise.
- `description` -> `_comments`: only set if `_comments` is currently Nothing. If
  the book already has a comment, it is kept unchanged.

Fields NOT touched: title, authors, publisher, published, rating, location,
series, custom. Those are either correct from Calibre or personal.

### Architecture

One new module, one modified:

`Libri.CLI.Enrich` (new):

- `needsEnrichment :: Book -> Bool` -- missing tags or comments, has ISBN
- `enrichBook :: Manager -> Book -> IO (Book, EnrichResult)` -- fetch and merge
- `runEnrich :: Config -> IO ()` -- CLI entry point with progress output
- `EnrichResult` ADT: `Enriched Int Bool | NotFound | AlreadyComplete | NoISBN`
  (tag count added, whether description was added)

Tag merge logic: `nub (existingTags ++ take 10 (filter notAlreadyPresent newTags))`
where `notAlreadyPresent` uses `normalizeText` for accent-insensitive comparison.

Changes to existing modules:

- `Commands.hs` -- add `CmdEnrich` to `Command`, wire `--enrich` flag, call
  `runEnrich`
- `OpenLibrary.hs` -- no changes needed. Reuse `fetchByISBNWith` with a shared
  manager.

## Out of Scope

- TUI integration (enrichment is CLI-only)
- Enriching books without ISBNs (title+author search)
- Overwrite mode for existing tags
- Dry-run mode
- Enriching publisher, published, or other already-complete fields
