# Expert Answers

Recorded: 2025-12-11

## Q11: YAML file organization
**Answer:** One YAML file per book (e.g., `books/978-0-13-468599-1.yaml`)

## Q12: CLI command style
**Answer:** Flag-based (e.g., `libri --add`, `libri --search "query"`)

## Q13: ISBN lookup behavior
**Answer:** Auto-fill all fields, let user edit before saving (verify before commit)

## Q14: Barcode scanning priority
**Answer:** Skip - not necessary since barcode reader works as keyboard input (types ISBN directly into any input field)

## Q15: Search and filtering
**Answer:** Full-text search including comments/descriptions, with fuzzy/typo-tolerant matching

## Q16: TUI layout
**Answer:** List view with details panel - book list on left, selected book details on right

## Q17: Calibre custom columns
**Answer:** Import as generic key-value pairs under a `custom` field

## Q18: Tool name
**Answer:** `libri` (Latin for "books")

---

## Summary of Technical Decisions

| Decision | Choice |
|----------|--------|
| Language | Haskell |
| TUI Framework | brick (recommended) |
| Storage Format | YAML (one file per book) |
| CLI Style | Flag-based |
| ISBN API | Open Library (primary) |
| Barcode | Not needed (hardware scanner) |
| Search | Full-text + fuzzy |
| Layout | List + details panel |
| Custom Fields | Generic key-value import |
| Project Name | libri |
