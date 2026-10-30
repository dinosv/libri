# Safe Calibre re-import

Date: 2026-10-29
Status: awaiting approval

## Why

libri is now the curated copy of the collection: tags have been merged
and cleaned, duplicates removed, records corrected by hand (e.g. the
private printing of *Ser y tiempo*), and books enriched from
OpenLibrary. Calibre is still where new books are catalogued first.
The user expects re-imports to bring in mostly newly added books.

Today `--import-calibre` is unsafe for that use. The full code review
(2026-10-29) found:

- `mergeBooks` (Storage/Yaml.hs) overwrites every field of a matched
  book with Calibre's values except id, location, added and custom, and
  drops identifiers that did not come from Calibre. A re-import would
  undo all curation.
- `findExistingBook` (Storage/CalibreImport.hs) ORs three match rules
  with no priority, falls back to the bare numeric Calibre ID (so a
  second Calibre library's book 5 merges into this library's book 5),
  and matches on ISBN even when the candidate belongs to a different
  Calibre record.
- `saveImportedBooks` matches against one snapshot taken before the
  loop, so two Calibre entries in the same import can collide.
- Calibre ISBNs stored with hyphens or whitespace are dropped
  (`extractIsbn` checks raw length 10/13), and Calibre's "no date"
  sentinel `0101-01-01` is stored as a real date.

## Goals

- Re-importing adds books that are new in Calibre, without questions.
- Books unchanged in Calibre since they were last imported are left
  completely alone, however much they were edited in libri.
- When a book has changed in Calibre, the user decides, per book or per
  field, which version to keep. Nothing in libri is overwritten without
  that decision.
- Books deleted in libri are not resurrected by a re-import.
- Books from a different Calibre library never merge into this one.

## Non-goals

- Syncing changes from libri back to Calibre.
- Importing covers or ebook files.
- Changing the first-time import of an empty library beyond what the
  matching rules require (it still just adds everything).

## Anti-goals (failure even if it "works")

- Prompting about hundreds of books on every import because libri and
  Calibre differ on purpose.
- Any silent overwrite of a libri field.
- Re-adding the three duplicate entries the user removed on 2026-10-29
  (Calibre ids 309, 351, 398 still exist in Calibre).

## Current data (facts the design must handle)

- 446 books, all with UUID ids after `--migrate-ids`.
- Every book carries `identifier:calibre` as a bare value: the old
  Calibre numeric id (e.g. `'46'`). One carries an ISBN instead
  (`'9780881792126'`), because its pre-migration id was an ISBN; this is
  not a real Calibre id.
- The Calibre library the data came from has library UUID
  `e9116e96-1573-4409-965e-8e0ee617fcdf`; a copy is at
  `calibre-source/Calibre Library/`.

## Design

### 1. Sync state file

A new file `<dataDir>/calibre-sync.yaml` records, per Calibre library:

- the library UUID and the path last imported from;
- whether it is this collection's home library: yes, no, or not yet
  answered;
- for every Calibre book seen: its namespaced reference
  (`<libraryUuid>:<calibreId>`), the libri book id it maps to (or a
  marker that it is ignored), and a fingerprint per field of the
  Calibre record as last imported.

Fingerprints are kept per field (title, authors, series, series index,
publisher, published, ISBN, tags, rating, comments, Calibre
identifiers), not one per book. This is what lets a conflict show only
the fields Calibre actually changed since the last import: a Calibre
edit to a book's comments must not put libri's curated tags or title in
front of the user, let alone let `c` overwrite them. Fingerprints must
be stable across runs, platforms and compiler versions; the digest and
canonical encoding are left to the builder (storing the last imported
values themselves is an acceptable alternative).

Libraries are identified by their Calibre library UUID. The path is
recorded for information only. A Calibre database whose library UUID
cannot be read is a hard error (today `getLibraryUuid` silently
returns `""`).

Book YAML files do not change format. The file lives outside
`books/`, so book loading and `--doctor` are unaffected.

### 2. Matching an incoming Calibre book

In strict priority order, first hit wins:

1. The sync state has an entry for the namespaced reference: use the
   recorded libri id (or skip if ignored). If the recorded libri book no
   longer exists, the user deleted it: skip and report it, never
   re-add.
2. A libri book whose `identifier:calibre` equals the namespaced
   reference.
3. Only for the library recorded as this collection's home library: a
   libri book whose bare `identifier:calibre` equals the Calibre numeric
   id. Never for any other library.
4. A libri book with the same normalised ISBN that has no
   `identifier:calibre` at all (i.e. a book added in libri, not from
   any Calibre library). This is a guess, so the user confirms it:
   same book, or add as a new book. "Same book" records the mapping and
   fingerprints, then shows every field where the two differ with the
   same `l`/`c`/`f` choice as a conflict (section 4); nothing is copied
   without that choice.
5. Otherwise the book is new.

Matching runs against the live in-memory collection, updated after
every book the import adds or merges, so entries within one import
cannot collide.

### 3. First re-import: the baseline

When the libri collection is empty, the import simply adds every book,
records mappings and fingerprints, and makes the library the home
library. No questions are asked.

Otherwise, when `calibre-sync.yaml` has no entry for the library being
imported, the import is a baseline run:

- It asks whether this library is the one the collection came from.
  Yes makes it the home library (enabling rule 3), replacing any
  previous home library: a Calibre library rebuilt with a new UUID but
  the same book ids is handled this way. No records it as a foreign
  library: rules 1, 2, 4 and 5 only. If the question cannot be
  answered, it stays unanswered and is asked again next time; it is
  never recorded as no by default.
- Matched books: record the mapping and the current fingerprint and
  change nothing. The user said existing books have not been edited in
  Calibre since April, so Calibre's current state is taken as the
  baseline.
- Unmatched Calibre books are listed (title, author, Calibre id). The
  user chooses: add all, ignore all, or decide one by one. Ignored
  books are recorded so later imports skip them. This is how the three
  deleted duplicates stay deleted.

### 4. Later re-imports

For each Calibre book:

- New (rule 5): added, with mapping and fingerprint recorded. Listed in
  the summary.
- Matched, fingerprint unchanged: nothing happens.
- Matched, some field fingerprints changed: a conflict, considering
  only the fields Calibre changed since the last import. libri shows
  the book title and, for each of those fields where Calibre's new
  value also differs from libri's current value, both values side by
  side. The user chooses:
  - `l`: keep libri's version of every field;
  - `c`: take Calibre's version of every differing field;
  - `f`: go field by field, choosing libri or Calibre for each; for
    tags, a third option takes the union;
  - `L`: keep libri for this and every remaining conflict in this run.
  If Calibre changed fields but libri already holds the same values,
  the fingerprints are updated silently.
- After any choice, the stored fingerprints are updated to Calibre's
  current ones, so the same Calibre change is not asked about again.

Fields libri owns are never touched by an import: id, location, added,
and custom fields that are not Calibre identifiers. Taking Calibre's
identifiers adds or updates `identifier:*` keys from Calibre; it never
removes identifiers libri has from elsewhere.

### 5. Non-interactive runs

When stdin is not interactive or reaches EOF, every question takes the
non-destructive answer: conflicts keep libri, ISBN guesses add nothing,
baseline unmatched books are neither added nor ignored (asked again next
time), and the home-library question stays unanswered (rule 3 is not
used in that run). The summary says
how many questions were left unanswered, and the command exits non-zero
if any were.

### 6. Calibre parsing fixes

- ISBNs are normalised (hyphens and whitespace removed, check digit
  `x` upper-cased) before the 10/13 length check.
- A publication or added date with year below 1000 (Calibre's
  `0101-01-01` sentinel) is treated as absent.

### 7. Summary and exit code

The run ends with counts: added, unchanged, conflicts resolved (by
choice), ignored, skipped as deleted in libri, unanswered, and
failures. Exit status is non-zero on any save failure.

## Decided by the user

- On a disagreement between Calibre and libri, the user chooses (not a
  fixed rule).
- Only Calibre-side changes since the last import count as conflicts;
  differences libri made on purpose are not raised.
- The first re-import takes Calibre's current state as the baseline.
- Tags on incoming books are taken as Calibre has them. Past
  `--tag-rename` merges are not remembered or re-applied; spelling
  variants that come back are found by `--doctor` and fixed by hand.

## Builder's calls

- Digest algorithm, canonical encoding and exact YAML layout of
  `calibre-sync.yaml`.
- Exact prompt wording and layout of the side-by-side display
  (comments may be long; truncation is fine if the user can still tell
  them apart).
- Module structure; keeping the matching and conflict logic pure and
  unit-tested, with a thin IO layer, as in the rest of the codebase.

## Settled by the designer (check these)

- Conflicts show only fields Calibre changed since the last import,
  following the user's decision; hence per-field fingerprints.
- The home-library answer can be unanswered; a yes on a later baseline
  run replaces the previous home library.
- An empty collection imports everything without questions.
- Rule 4 only considers books with no Calibre provenance at all.
- The bogus provenance value `identifier:calibre: '9780881792126'` on
  *The Elements of Typographic Style* (its pre-migration id was an
  ISBN; the book is not in Calibre) is removed as part of this work, so
  rule 4 can match it if Calibre ever gains the book.

## Amendments after the final review (2026-10-29)

Rulings made by the controller during the final whole-branch review:

- Home status gains a fourth value, former. Answering yes for a new
  home library demotes the previous home library to former, not no.
  Rule 3 for the home library also matches a libri book whose
  `identifier:calibre` is `<u>:<calibreId>` for any former home
  library `u`, so books imported from the old library are still found
  after a rebuild with a new UUID.
- Rule 4 skips libri books that a sync entry of this library already
  maps to, including entries recorded earlier in the same run.
- Conflicts (sections 2 and 4) do not raise identifiers as a differing
  field when taking Calibre's identifiers would not change libri's.
- The empty-collection shortcut (section 3) applies only when the sync
  state has no book entries for the library; otherwise the normal flow
  runs, so ignored and deleted books stay out.
- An interrupted run (Ctrl-C) saves the sync state reached so far. On
  an interrupted baseline run, every incoming book without an entry is
  recorded as pending, so the next run still asks about it.
- When the truncated displays of a field look the same on both sides,
  the side-by-side shows a window around the first difference, with
  whitespace made visible.
