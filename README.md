# libri

A TUI/CLI tool for managing a physical book collection.

## Features

- **TUI Interface**: Browse and search your book collection with a terminal UI
- **CLI Commands**: Quick operations via command-line flags
- **Calibre Import**: One-time migration from Calibre library
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
