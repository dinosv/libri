# Expert Questions

Generated: 2025-12-11
Based on: Discovery answers + Technology research

---

## Q11: How should book data be organized in YAML files?

For 500-2000 books with full metadata, what file structure do you prefer?

1. **One YAML file per book** (e.g., `books/978-0-13-468599-1.yaml`) [default - easier git diffs, parallel edits]
2. **Single books.yaml file** - simpler but harder to manage at scale
3. **Grouped files** (e.g., `books/by-author/thomas-david.yaml`) - organized but complex
4. Other (please specify)

**Why this matters:**
With 500-2000 books, one file per book (~1-2KB each) keeps diffs clean, allows easy manual editing of individual books, and avoids merge conflicts if you version control. Single file gets unwieldy but loads faster.

---

## Q12: CLI command style preference?

How should CLI commands be structured?

1. **Git-style subcommands** (e.g., `bookman add`, `bookman move`, `bookman search`) [default - familiar pattern]
2. **Flag-based** (e.g., `bookman --add`, `bookman --search "query"`)
3. **Interactive prompts** when arguments missing
4. Other (please specify)

---

## Q13: What ISBN lookup behavior do you want?

When adding a book by ISBN:

1. **Auto-fill all fields, let user edit before saving** [default - verify before commit]
2. **Auto-fill and save immediately, edit later if needed**
3. **Show fetched data, ask confirmation for each field**
4. Other (please specify)

---

## Q14: Barcode scanning priority?

How important is barcode scanning for v1?

1. **Essential for v1** - I have many books to add quickly
2. **Nice to have** - can add manually or by ISBN typing
3. **Skip for v1** - implement later [default - reduces scope]
4. Other (please specify)

---

## Q15: Search and filtering needs?

What search capabilities do you need?

1. **Basic text search** across title/author/tags [default - covers most needs]
2. **Advanced filtering** (by location, date range, rating, custom fields)
3. **Full-text search** including comments/descriptions
4. **Fuzzy search** with typo tolerance
5. All of the above

---

## Q16: TUI layout preference?

What kind of TUI layout do you envision?

1. **List view with details panel** - book list on left, selected book details on right [default - common pattern]
2. **Full-screen list** - show all info in columns, expand on select
3. **Card/grid view** - visual browsing with covers
4. **Tabbed interface** - different tabs for browse, search, add, etc.
5. Other (please specify)

---

## Q17: How should the tool handle Calibre custom columns?

Calibre allows custom metadata columns. How should we handle them?

1. **Import as generic key-value pairs** under a `custom` field [default - flexible]
2. **Let user define schema** for custom fields in a config file
3. **Ignore custom columns** - only import standard fields
4. Other (please specify)

---
