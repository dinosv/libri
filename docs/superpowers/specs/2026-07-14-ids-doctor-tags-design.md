# UUID migration, doctor, and tag management

Date: 2026-07-14
Status: approved

## Motivation

- Book IDs are a mix of Calibre auto-increment integers (all 449 books
  today), ISBNs and UUIDs; a second Calibre import would silently
  merge unrelated books that share a numeric ID.
- The data holds at least five duplicate ISBNs, so ISBN cannot be the
  primary key.
- 290 distinct tags include case/accent spelling variants
  ("Public Health" vs "Public health") with no tooling to fix them.
- No whole-collection integrity check exists.

## 1. IDs, filenames, save semantics

- Book IDs are UUIDs. `newBook`, the TUI add form, OpenLibrary
  fetches and Calibre imports all mint UUIDs (previously ISBN or
  Calibre ID was used as the ID).
- Filenames decouple from IDs: `slug(title)-<shortid>.yaml`, where
  `slug` is accent-folded, lowercased, non-alphanumerics collapsed to
  single hyphens, trimmed, capped at 40 chars, falling back to "book"
  for empty titles; `<shortid>` is the first 8 alphanumeric characters
  of the ID.
- The shortid suffix is the identity anchor. `saveBook` writes the
  canonical filename, then deletes any sibling file that belongs to
  the same book: a file ending in `-<shortid>.yaml`, or the legacy
  `<sanitised-id>.yaml` name. Title renames therefore rename the file
  transparently, and legacy files are cleaned up on first save.
- `deleteBook` locates the file the same way (canonical name, shortid
  suffix, legacy name).
- Loading is filename-agnostic (reads all `*.yaml`), so old and new
  names coexist during transition.

## 2. `libri --migrate-ids`

- Scope: every book whose ID is not a UUID, or whose filename is not
  canonical.
- For non-UUID IDs: mint a UUID; preserve the old ID as custom field
  `identifier:calibre` (bare value, e.g. "100") unless already
  present. For UUID IDs with stale filenames: rename only.
- Writes preserve `modified` (direct atomic write, not `saveBook`);
  old file removed after the new one is written.
- Prints the full plan (old id -> new id, old file -> new file),
  recommends committing the data directory first, asks y/N
  (EOF-safe; default no). Idempotent: a second run reports nothing
  to do.

## 3. Calibre import matching

- Imported books carry custom field `identifier:calibre` =
  `<libraryUuid>:<bookId>`, where libraryUuid comes from Calibre's
  `library_id` table (empty prefix if unavailable).
- `saveImportedBooks` matches existing books, in order: by
  `identifier:calibre` (accepting both `<libraryUuid>:<N>` and the
  bare `<N>` written by migration), then by normalised ISBN, then by
  legacy bookId == Calibre numeric ID. On match, `mergeBooks` keeps
  the existing ID/location/added/custom as today.
- This fixes the cross-library collision properly: books from a
  different library carry a different library UUID and distinct
  fresh UUIDs, so they can never merge with or overwrite books from
  the first library by accident.

## 4. `libri --doctor` (read-only)

Reports, in sections, each with counts and details:

1. Unparseable book files (path + error).
2. Stray `.tmp` files in the books directory.
3. Duplicate ISBNs (normalised), listing IDs and titles.
4. Duplicate IDs.
5. Legacy/stale filenames (actual /= canonical) — suggests
   `--migrate-ids`.
6. Empty or whitespace-only tags.
7. Tag spelling variants: tags equal under `normalizeText` but
   spelled differently, with per-spelling counts — suggests
   `--tag-rename`.
8. Locations used by books but absent from locations.yaml.

Exit code 0 when clean, 1 when any issue is found. Doctor never
writes.

## 5. Tag commands

- `libri --tag-rename OLD --to NEW`: every tag normalised-equal to
  OLD becomes NEW (verbatim); tags are deduplicated within each book
  afterwards (renaming onto an existing tag merges). Prints books
  changed. No-op when nothing matches.
- `libri --tag-delete TAG`: removes every tag normalised-equal to
  TAG. Prints books changed.
- Both save through `saveBook` (bumps `modified`, renames legacy
  files as a side effect).

## Components

- `Libri.Text.Normalize`: add `slugify`.
- `Libri.Types`: `bookFilename` becomes slug+shortid; add
  `bookShortId`.
- `Libri.Storage.Yaml`: save/delete file location by shortid suffix
  and legacy name.
- `Libri.Storage.CalibreImport`: library UUID read, identifier
  stamping, new matching in `saveImportedBooks`.
- `Libri.ISBN.OpenLibrary`: UUID for fetched books.
- New modules: `Libri.CLI.Doctor`, `Libri.CLI.Tags`,
  `Libri.CLI.Migrate` (each: pure analysis/transform core + thin IO
  runner).
- `Libri.CLI.Commands`: `--doctor`, `--migrate-ids`,
  `--tag-rename OLD --to NEW`, `--tag-delete TAG`.

## Testing

- Pure: slugify (Spanish titles, punctuation, length cap, empty);
  filename/shortid; tag rename/merge/dedupe semantics; doctor checks
  (variant grouping, duplicate ISBN grouping).
- IO (temp dirs): save renames a legacy file and a title-changed
  file; deleteBook finds legacy names; migration converts and is
  idempotent; doctor exit behaviour.
- End-to-end (verify skill): scratch copy of a few real files —
  doctor report, tag rename, migration run, TUI still loads.
  The live-data migration run is left to the user after a data
  commit.

## Out of scope

Bulk tag operations in the TUI (separate design), automatic tag-case
harmonisation (doctor reports, user decides), SQLite or caching.
