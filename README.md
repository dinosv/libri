# libri

A TUI/CLI tool for managing a physical book collection.

## Features

- **TUI Interface**: Browse and search your book collection with a terminal UI
- **CLI Commands**: Quick operations via command-line flags
- **Calibre import and safe re-import**: Import a Calibre library, and run it again later without losing edits made in libri
- **ISBN Lookup**: Fetch book metadata from Open Library
- **Fuzzy Search**: Find books even with typos
- **YAML Storage**: Human-readable, git-friendly book files

## Installation

```bash
cabal build
cabal install
```

## Usage

### TUI Mode (default)

```bash
libri
```

### CLI Commands

```bash
# Add book by ISBN
libri --add --isbn 978-0-13-468599-1 --location "Office Shelf A"

# Search books
libri --search "pragmatic programmer"

# Move book to different location
libri --move --isbn 978-0-13-468599-1 --to "Living Room"

# List all locations
libri --locations

# Import from Calibre
libri --import-calibre /path/to/calibre/library
```

### Re-importing from Calibre

Running `--import-calibre` again is safe: nothing in libri is changed
without your say-so. The first import into an empty collection simply adds
every book. Otherwise libri behaves as follows.

The first re-import of a Calibre library is the baseline run. libri asks
whether this is the Calibre library your collection came from; answering
yes lets books be matched by their Calibre id. Books already in libri are
matched and left untouched. Calibre books not in your collection are then
listed, and you choose to add all, ignore all, or decide one by one.
Ignored books stay out on later runs.

On later runs:

- books new in Calibre are added without asking;
- books unchanged in Calibre since the last import are left alone, however
  much you have edited them in libri;
- when Calibre has changed a field and its new value differs from libri's,
  you choose: keep libri's version, take Calibre's, go field by field, or
  keep libri's for all remaining conflicts in this run. Field by field, tags
  can also be merged (the union of both).

When a Calibre book has the same ISBN as a libri book that did not come
from Calibre, you are asked whether it is the same book or a new one.
Books you have deleted in libri are never added back.

Questions left unanswered (because input ran out) are asked again next
time, and the command exits with an error. Pressing Ctrl-C keeps the
answers given so far.

What libri knows about each Calibre library is kept in
`<dataDir>/calibre-sync.yaml`. To change a "no" to the home-library
question, set that library's `home:` to `unanswered` in this file; the
question is then asked again on the next import. If Calibre is rebuilt
with a new library id, answer yes for the new library: books from the
previous home library are still recognised.

## Keyboard Shortcuts (TUI)

- `j`/`k` or arrows: Navigate list
- `/`: Search
- `a`: Add new book
- `e`: Edit selected book
- `d`: Delete selected book
- `m`: Move book to location
- `q`: Quit

## Data Storage

Books are stored as individual YAML files in `~/.local/share/libri/books/`.

Example book file:
```yaml
id: "978-0-13-468599-1"
title: "The Pragmatic Programmer"
authors:
  - "David Thomas"
  - "Andrew Hunt"
location: "Office Shelf A"
tags:
  - programming
rating: 5
```

## License

MIT
