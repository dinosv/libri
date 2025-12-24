# Research Findings (New Project)

Generated: 2025-12-11

Since this is a new project, this phase covers technology research rather than codebase analysis.

---

## Technology Stack Research

### Haskell TUI Framework: brick

**Recommendation:** [brick](https://hackage.haskell.org/package/brick) - the most mature and well-documented Haskell TUI library.

**Key Features:**
- Declarative UI: write pure functions describing how UI should be drawn
- Built on vty for terminal I/O
- High-level application abstraction
- Supports Windows as of Vty 6
- Active development (version 2.x in 2025)

**Resources:**
- [Official GitHub](https://github.com/jtdaugherty/brick)
- [User Guide](https://github.com/jtdaugherty/brick/blob/master/docs/guide.rst)
- [Sam Tay's Tutorial](https://samtay.github.io/posts/introduction-to-brick) (older but conceptually useful)

**Similar projects built with brick:**
- hledger-ui (accounting TUI)
- matterhorn (Mattermost client)
- Tetris clone
- Spaced-repetition memorization tool

---

### ISBN/Book Metadata APIs

**Primary Recommendation:** [Open Library API](https://openlibrary.org/developers/api) (Free)

- ~30 million titles
- ISBN lookup: `/isbn/{isbn10_or_13}`
- No authentication required for basic lookups
- Returns: title, authors, publishers, cover images, page count

**Backup:** [Google Books API](https://developers.google.com/books/docs/v1/using)
- 40+ million titles
- No authentication for searches
- Query by ISBN: `isbn:{number}`

---

### Data Storage: YAML vs TOML

**For book collection data, YAML is recommended:**

**YAML Libraries:**
- [yaml](https://hackage.haskell.org/package/yaml) - most popular, aeson-based, supports `!include`
- [HsYAML](https://hackage.haskell.org/package/HsYAML) - pure Haskell, YAML 1.2 compliant

**TOML Libraries:**
- [tomland](https://hackage.haskell.org/package/tomland) - bidirectional, pretty-printing
- [toml-parser](https://hackage.haskell.org/package/toml-parser) - TOML 1.0.0 compliant

**Recommendation:** YAML with `yaml` package
- Better for nested/complex data (custom columns, multiple authors)
- More readable for lists
- Well-integrated with aeson ecosystem

---

### Barcode Scanning

Options for Haskell:
1. **Shell out to zbar** (`zbarimg` CLI) - most practical
2. **FFI bindings to zbar** - more work but native
3. **Capture image, send to web API** - requires camera handling

---

### Calibre Database Import

Calibre uses SQLite (`metadata.db`). Haskell options:
- [sqlite-simple](https://hackage.haskell.org/package/sqlite-simple) - high-level SQLite
- [persistent-sqlite](https://hackage.haskell.org/package/persistent-sqlite) - type-safe ORM

Schema reference: [calibre/resources/metadata_sqlite.sql](https://github.com/kovidgoyal/calibre/blob/master/resources/metadata_sqlite.sql)

---

## Architecture Recommendations

### Project Structure
```
calibre-book-manager/
├── app/
│   └── Main.hs              -- Entry point
├── src/
│   ├── Types.hs             -- Core data types (Book, Location, etc.)
│   ├── Storage/
│   │   ├── Yaml.hs          -- YAML read/write
│   │   └── CalibreImport.hs -- One-time Calibre import
│   ├── TUI/
│   │   ├── App.hs           -- Brick application
│   │   ├── Views/           -- Different screens
│   │   └── Widgets/         -- Reusable widgets
│   ├── CLI/
│   │   └── Commands.hs      -- CLI command handlers
│   ├── ISBN/
│   │   └── Lookup.hs        -- OpenLibrary/Google Books API
│   └── Barcode/
│       └── Scanner.hs       -- Barcode scanning integration
├── data/
│   └── books/               -- YAML book files
├── calibre-book-manager.cabal
└── README.md
```

### Data File Structure (YAML)
```yaml
# books/978-0-13-468599-1.yaml
isbn: "978-0-13-468599-1"
title: "The Pragmatic Programmer"
authors:
  - "David Thomas"
  - "Andrew Hunt"
series: null
series_index: null
publisher: "Addison-Wesley"
published: 2019-09-13
tags:
  - programming
  - software-engineering
rating: 5
location: "Office Shelf A"
custom:
  condition: "Like New"
  purchase_date: "2020-01-15"
  purchase_price: 45.99
added: 2025-12-11T20:30:00Z
```

---

## Key Technical Decisions Needed

1. **CLI framework:** optparse-applicative vs cmdargs
2. **One file per book vs single YAML file:** scalability vs simplicity
3. **HTTP client:** http-client vs wreq vs req
4. **Barcode approach:** zbar CLI vs native vs skip for v1
5. **Search strategy:** in-memory vs indexed
