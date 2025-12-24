# Calibre ISBN Import Fix

**Date:** 2024-12-24
**Status:** Approved

## Problem

The Calibre import (`--import-calibre`) does not copy ISBN numbers. The current code explicitly sets `_isbn = Nothing` because Calibre stores identifiers in a separate `identifiers` table, not the main `books` table.

## Solution Overview

Query Calibre's `identifiers` table during import:
- ISBN goes into the `_isbn` field (ISBN-13 preferred, fallback to ISBN-10)
- Other identifiers (ASIN, Google Books ID, etc.) go into `_custom` with prefix `identifier:`

## Decisions

| Question | Decision |
|----------|----------|
| Which identifiers to import? | ISBN in `_isbn`, all others in `_custom` |
| Multiple ISBNs? | Prefer ISBN-13, fallback to ISBN-10 |
| Existing books? | Re-import to update; fix applies to future imports too |
| Merge strategy? | Calibre data wins, but preserve libri-only fields (`_location`, non-identifier custom fields) |
| Identifier naming in custom? | Prefixed: `identifier:asin`, `identifier:google`, etc. |
| Book matching? | By `_bookId` (Calibre's internal ID) |

## Database Query

```sql
SELECT type, val FROM identifiers WHERE book = ?
```

Returns rows like:

| type | val |
|------|-----|
| isbn | 9780134685991 |
| amazon | B07N1XLQ7D |

## Processing Logic

1. Query all identifiers for the book
2. Separate ISBNs by length: 13 digits = ISBN-13, 10 digits = ISBN-10
3. Select ISBN-13 if available, otherwise ISBN-10 → `_isbn`
4. Prefix remaining identifiers → `_custom["identifier:type"] = val`

## Merge Strategy

**Calibre-owned fields (overwritten on re-import):**
- `_title`, `_authors`, `_series`, `_seriesIndex`
- `_publisher`, `_published`, `_tags`, `_rating`, `_comments`
- `_isbn`
- `_custom` entries with `identifier:*` prefix
- `_modified`

**Libri-owned fields (preserved on re-import):**
- `_location`
- `_custom` entries without `identifier:` prefix
- `_added`
- `_bookId`

## Files to Modify

### `src/Libri/Storage/CalibreImport.hs`

- Add `getIdentifiers :: Connection -> Int -> IO (Map Text Text)`
- Modify `importBooks` to call `getIdentifiers`
- Modify `convertBook` to extract ISBN and prefix other identifiers

### `src/Libri/Storage/Yaml.hs`

- Add merge logic before saving
- Load existing book if file exists
- Preserve libri-owned fields
- Save merged result

## Error Handling

| Scenario | Handling |
|----------|----------|
| No identifiers | `_isbn` stays `Nothing`, no entries in `_custom` |
| Identifiers table missing | Catch error, log warning, continue without identifiers |
| Malformed ISBN | Store as-is; validation is separate concern |
| Corrupted existing file | Log error, skip merge, save fresh Calibre data |
| Multiple ISBN entries | Collect all, prefer ISBN-13, else first ISBN-10 |

## Testing

1. Unit test: `getIdentifiers` with mock data
2. Unit test: ISBN-13 vs ISBN-10 selection logic
3. Integration test: import sample Calibre DB, verify ISBN in YAML
4. Merge test: import twice, verify `_location` preserved
