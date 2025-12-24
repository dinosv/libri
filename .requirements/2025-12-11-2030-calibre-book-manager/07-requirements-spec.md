# libri - Physical Book Collection Manager

**Created:** 2025-12-11T20:30:00Z
**Status:** draft
**Last Updated:** 2025-12-11T21:00:00Z

---

## Overview

**libri** is a Haskell TUI/CLI application for managing a physical book collection. It provides a full terminal user interface for browsing and searching books, with flag-based CLI commands for quick operations like adding new volumes or moving books between locations.

The tool imports data from an existing Calibre library (one-time migration) and then operates independently using human-readable YAML files for storage. This replaces Calibre for physical book management while maintaining all metadata including custom columns.

Key features:
- **TUI-first design** with brick framework - list view with details panel
- **Flag-based CLI** for scripting and quick operations
- **Multiple book input sources:** Calibre import, ISBN lookup (Open Library API), manual entry
- **Full-text fuzzy search** across all book metadata
- **Simple flat locations** for tracking physical book placement
- **YAML storage** - one file per book, human-readable and git-friendly

---

## Implementation Strategy

### Recommended Skill
**Skill:** `developer`

**Rationale:**
This is a new Haskell application requiring:
- TUI development with brick framework
- CLI argument parsing
- YAML file I/O
- HTTP client for ISBN lookup
- SQLite reading for Calibre import
- Fuzzy text search implementation

**To implement:** Run `/implement calibre-book-manager` which will invoke the `developer` skill.

---

## Requirements

### Functional Requirements

1. **Browse Collection**
   - Display all books in a scrollable list
   - Show book details in a side panel when selected
   - Sort by title, author, date added, rating

2. **Search Books**
   - Full-text search across all fields (title, authors, tags, comments, custom fields)
   - Fuzzy matching with typo tolerance
   - Filter by location

3. **Add Books**
   - Via ISBN: fetch metadata from Open Library API, edit before saving
   - Manual entry: form-based input in TUI or CLI flags
   - Barcode scanner: works via keyboard input (no special handling needed)

4. **Import from Calibre**
   - One-time import from Calibre's `metadata.db`
   - Import all standard fields + custom columns
   - Custom columns stored as key-value pairs

5. **Manage Locations**
   - Assign books to physical locations (flat list, e.g., "Office Shelf A")
   - Move books between locations
   - View all books at a location

6. **Edit Books**
   - Edit any field via TUI form or CLI
   - Delete books from collection

### User Interactions

**TUI Mode (default):**
```
$ libri
┌─ Books (1,247) ────────────────┬─ Details ──────────────────────┐
│ > The Pragmatic Programmer     │ Title: The Pragmatic Programmer│
│   Clean Code                   │ Authors: David Thomas,         │
│   Domain-Driven Design         │          Andrew Hunt           │
│   Designing Data-Intensive App │ ISBN: 978-0-13-468599-1        │
│   ...                          │ Publisher: Addison-Wesley      │
│                                │ Published: 2019                │
│                                │ Rating: ★★★★★                  │
│                                │ Location: Office Shelf A       │
│                                │ Tags: programming, software    │
│ [/] Search  [a] Add  [e] Edit  │                                │
│ [m] Move    [d] Delete  [q] Quit│ Custom:                       │
└────────────────────────────────┴─ condition: Like New ──────────┘
```

**CLI Mode (flag-based):**
```bash
# Add book by ISBN
libri --add --isbn 978-0-13-468599-1 --location "Office Shelf A"

# Search
libri --search "pragmatic programmer"

# Move book
libri --move --isbn 978-0-13-468599-1 --to "Living Room"

# List locations
libri --locations

# Import from Calibre
libri --import-calibre /path/to/calibre/library

# Launch TUI (default)
libri
```

---

## Technical Implementation

### Technology Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language | Haskell | User preference |
| TUI Framework | [brick](https://hackage.haskell.org/package/brick) | Most mature Haskell TUI, declarative |
| CLI Parsing | optparse-applicative | Standard, type-safe |
| YAML | [yaml](https://hackage.haskell.org/package/yaml) | aeson-based, well-supported |
| HTTP Client | http-client + aeson | For Open Library API |
| SQLite | sqlite-simple | For Calibre import |
| Fuzzy Search | [fuzzy](https://hackage.haskell.org/package/fuzzy) or custom | Typo-tolerant matching |

### Project Structure

```
libri/
├── app/
│   └── Main.hs                    -- Entry point, CLI/TUI dispatcher
├── src/
│   └── Libri/
│       ├── Types.hs               -- Core types: Book, Location, Config
│       ├── Storage/
│       │   ├── Yaml.hs            -- YAML read/write operations
│       │   ├── Index.hs           -- In-memory book index
│       │   └── CalibreImport.hs   -- One-time Calibre migration
│       ├── TUI/
│       │   ├── App.hs             -- Brick application state & events
│       │   ├── Views/
│       │   │   ├── BookList.hs    -- Main list view
│       │   │   ├── BookDetails.hs -- Details panel
│       │   │   ├── AddBook.hs     -- Add/edit form
│       │   │   └── Search.hs      -- Search interface
│       │   └── Widgets/
│       │       └── Common.hs      -- Shared widgets
│       ├── CLI/
│       │   └── Commands.hs        -- Flag-based command handlers
│       ├── Search/
│       │   └── Fuzzy.hs           -- Full-text fuzzy search
│       └── ISBN/
│           └── OpenLibrary.hs     -- ISBN lookup via Open Library API
├── data/                          -- Default data directory
│   ├── config.yaml                -- App configuration
│   ├── locations.yaml             -- List of locations
│   └── books/                     -- Book YAML files
│       └── *.yaml
├── libri.cabal
├── cabal.project
└── README.md
```

### Data Structures

**Book Type (Types.hs):**
```haskell
data Book = Book
  { bookId        :: Text           -- UUID or ISBN
  , isbn          :: Maybe Text
  , title         :: Text
  , authors       :: [Text]
  , series        :: Maybe Text
  , seriesIndex   :: Maybe Double
  , publisher     :: Maybe Text
  , published     :: Maybe Day
  , tags          :: [Text]
  , rating        :: Maybe Int      -- 1-5
  , comments      :: Maybe Text
  , location      :: Maybe Text     -- Physical location
  , custom        :: Map Text Value -- Calibre custom columns
  , added         :: UTCTime
  , modified      :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON Book
instance FromJSON Book
```

**Book YAML File Example:**
```yaml
# books/978-0-13-468599-1.yaml
id: "978-0-13-468599-1"
isbn: "978-0-13-468599-1"
title: "The Pragmatic Programmer"
authors:
  - "David Thomas"
  - "Andrew Hunt"
series: null
seriesIndex: null
publisher: "Addison-Wesley Professional"
published: 2019-09-13
tags:
  - programming
  - software-engineering
  - best-practices
rating: 5
comments: |
  20th Anniversary Edition. Essential reading for any developer.
  Covers topics from career advice to coding practices.
location: "Office Shelf A"
custom:
  condition: "Like New"
  purchase_date: "2020-01-15"
  purchase_price: 45.99
  read_status: "Read"
added: 2025-12-11T20:30:00Z
modified: 2025-12-11T20:30:00Z
```

**Configuration (config.yaml):**
```yaml
dataDir: "./data/books"
defaultLocation: null
isbnApi: "openlibrary"  # or "googlebooks"
fuzzyThreshold: 0.6
```

**Locations (locations.yaml):**
```yaml
locations:
  - "Office Shelf A"
  - "Office Shelf B"
  - "Living Room Bookcase"
  - "Bedroom Nightstand"
  - "Storage Box 1"
  - "Lent Out"
```

### Open Library API Integration

**Endpoint:** `https://openlibrary.org/isbn/{isbn}.json`

**Response mapping:**
```haskell
-- OpenLibrary response -> Book
fetchByISBN :: Text -> IO (Either Error Book)
fetchByISBN isbn = do
  -- GET https://openlibrary.org/isbn/{isbn}.json
  -- Parse response, map fields:
  --   title -> title
  --   authors -> fetch from /authors/{key}.json
  --   publishers[0] -> publisher
  --   publish_date -> published
  --   number_of_pages -> custom.pages
```

### Calibre Import

**Key tables in metadata.db:**
- `books` - core book data
- `authors` + `books_authors_link` - author relationships
- `tags` + `books_tags_link` - tag relationships
- `series` + `books_series_link` - series info
- `custom_column_*` - custom columns (dynamic)

**Import process:**
1. Read `metadata.db` with sqlite-simple
2. Query all books with JOINs for authors, tags, series
3. Detect custom columns from `custom_columns` table
4. Convert each book to YAML and write to `books/` directory
5. Generate `locations.yaml` from custom "location" column if present

### Fuzzy Search Implementation

**Approach:** Build in-memory index on startup, use fuzzy string matching.

```haskell
data SearchIndex = SearchIndex
  { allBooks     :: [Book]
  , titleIndex   :: Map Text [Book]  -- word -> books
  , authorIndex  :: Map Text [Book]
  , tagIndex     :: Map Text [Book]
  }

search :: SearchIndex -> Text -> [Book]
search idx query =
  -- 1. Tokenize query
  -- 2. Fuzzy match each token against indices
  -- 3. Score and rank results
  -- 4. Return top matches
```

Consider using [fuzzy](https://hackage.haskell.org/package/fuzzy) or [fuzzyset](https://hackage.haskell.org/package/fuzzyset) packages.

---

## Implementation Guide

### Step-by-Step Approach

1. **Project Setup**
   - Initialize cabal project with dependencies
   - Set up basic module structure
   - Define core types (Book, Config)

2. **Storage Layer**
   - Implement YAML read/write for books
   - Build in-memory index structure
   - Add file watching or manual refresh

3. **CLI Foundation**
   - Set up optparse-applicative
   - Implement `--help`, `--version`
   - Add `--import-calibre` command first (for testing)

4. **Calibre Import**
   - Connect to metadata.db
   - Map Calibre schema to Book type
   - Handle custom columns dynamically
   - Write YAML files

5. **ISBN Lookup**
   - Implement Open Library API client
   - Parse JSON responses
   - Handle errors gracefully

6. **TUI - Basic**
   - Set up brick application skeleton
   - Implement book list view
   - Add keyboard navigation

7. **TUI - Details Panel**
   - Implement split layout
   - Show selected book details
   - Style with brick attributes

8. **Search**
   - Implement fuzzy search algorithm
   - Add search input widget
   - Filter list in real-time

9. **Add/Edit Forms**
   - Create form widgets
   - ISBN lookup integration
   - Validation and saving

10. **Location Management**
    - Move command
    - Location filter/view
    - New location creation

### Testing Strategy

- **Unit tests:** Pure functions (search, parsing, type conversions)
- **Integration tests:** YAML round-trip, API mocking
- **Manual testing:** TUI interaction, Calibre import with real data

---

## Edge Cases & Constraints

### Edge Cases to Handle

- Books without ISBN (manual entry, old books)
- Multiple books with same ISBN (different editions owned)
- Unicode in titles/authors (proper text handling)
- Very long comments/descriptions (truncation in list view)
- Missing fields from Open Library (graceful defaults)
- Corrupt or incomplete Calibre database

### Technical Constraints

- **Haskell ecosystem:** Fewer TUI examples than Python, but brick is solid
- **Open Library API:** No authentication, but rate limits may apply
- **YAML file I/O:** Must handle concurrent access if multiple instances
- **Memory:** Loading 2000 books into memory is fine (~10-20MB)

### Performance Considerations

- **Startup:** Load all YAML files into memory (acceptable for 2000 books)
- **Search:** In-memory fuzzy search, should be instant
- **File I/O:** Write individual files, not full collection

---

## Acceptance Criteria

- [ ] TUI launches and displays book list with details panel
- [ ] Can navigate list with keyboard (j/k or arrows)
- [ ] Search filters books with fuzzy matching
- [ ] Can add book by ISBN (fetches from Open Library)
- [ ] Can add book manually via form
- [ ] Can edit existing book
- [ ] Can delete book
- [ ] Can assign/change book location
- [ ] CLI commands work: `--add`, `--search`, `--move`, `--locations`
- [ ] Calibre import works with standard fields
- [ ] Calibre import preserves custom columns
- [ ] Books stored as individual YAML files
- [ ] YAML files are human-readable and editable

---

## Implementation Checklist

- [ ] Initialize Haskell project with cabal
- [ ] Add dependencies: brick, vty, yaml, aeson, optparse-applicative, sqlite-simple, http-client, fuzzy
- [ ] Define `Book` and related types in `Types.hs`
- [ ] Implement YAML storage in `Storage/Yaml.hs`
- [ ] Implement Calibre import in `Storage/CalibreImport.hs`
- [ ] Implement Open Library client in `ISBN/OpenLibrary.hs`
- [ ] Implement fuzzy search in `Search/Fuzzy.hs`
- [ ] Set up CLI parsing in `CLI/Commands.hs`
- [ ] Build TUI app skeleton in `TUI/App.hs`
- [ ] Implement list view in `TUI/Views/BookList.hs`
- [ ] Implement details panel in `TUI/Views/BookDetails.hs`
- [ ] Implement search widget in `TUI/Views/Search.hs`
- [ ] Implement add/edit form in `TUI/Views/AddBook.hs`
- [ ] Wire everything together in `Main.hs`
- [ ] Test with sample Calibre library
- [ ] Write basic documentation

---

## References

### Haskell Libraries

- [brick](https://hackage.haskell.org/package/brick) - TUI framework
- [brick user guide](https://github.com/jtdaugherty/brick/blob/master/docs/guide.rst)
- [vty](https://hackage.haskell.org/package/vty) - Terminal library (brick dependency)
- [yaml](https://hackage.haskell.org/package/yaml) - YAML parsing
- [optparse-applicative](https://hackage.haskell.org/package/optparse-applicative) - CLI parsing
- [sqlite-simple](https://hackage.haskell.org/package/sqlite-simple) - SQLite access
- [fuzzy](https://hackage.haskell.org/package/fuzzy) - Fuzzy string matching

### APIs

- [Open Library API](https://openlibrary.org/developers/api) - ISBN lookup
- [Open Library Books API](https://openlibrary.org/dev/docs/api/books) - Book metadata
- [Google Books API](https://developers.google.com/books/docs/v1/using) - Backup ISBN source

### Calibre

- [Calibre DB API docs](https://manual.calibre-ebook.com/db_api.html)
- [Calibre SQLite schema](https://github.com/kovidgoyal/calibre/blob/master/resources/metadata_sqlite.sql)

### Example Projects

- [hledger-ui](https://github.com/simonmichael/hledger) - brick-based accounting TUI
- [matterhorn](https://github.com/matterhorn-chat/matterhorn) - brick-based chat client

---

## Notes

### Assumptions Made

- User has a working Haskell/cabal setup
- Calibre library is accessible (local path to metadata.db)
- Internet access for ISBN lookups (graceful offline fallback)
- Terminal supports Unicode and 256 colors

### Future Enhancements (Out of Scope for v1)

- Cover image display (terminal graphics)
- Reading progress tracking
- Lending history
- Statistics/analytics
- Export to other formats
- Mobile companion app
- Web interface via brick-server

### Alternative Approaches Considered

- **SQLite instead of YAML:** More robust querying but less human-readable
- **Single YAML file:** Simpler but poor for large collections and git
- **Python/Textual:** Better ecosystem but user prefers Haskell
- **Rust/ratatui:** Good performance but user chose Haskell
