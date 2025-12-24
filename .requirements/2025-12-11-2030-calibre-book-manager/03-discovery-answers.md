# Discovery Answers

Recorded: 2025-12-11

## Q1: Primary use case
**Answer:** Browse and search physical book collection; add volumes through different sources and mechanisms; track where books are physically located.

## Q2: Interface preference
**Answer:** Full TUI as primary interface with CLI commands for quick operations (adding new volumes, moving volumes between locations). TUI-first approach.

**Additional note:** Database should be as simple as possible; plain text preferred if feasible.

## Q3: Calibre data importance
**Answer:** Full metadata including custom columns.

## Q4: Book sources
**Answer:** All of the mentioned:
- Import from Calibre database
- ISBN lookup (fetch metadata from online sources)
- Manual entry
- Barcode scanning (camera/scanner)

## Q5: Calibre sync
**Answer:** Read-only import from Calibre. User plans to not use Calibre anymore - this tool will replace it.

## Q6: Collection size
**Answer:** Medium (500-2000 books)

## Q7: Programming language
**Answer:** Haskell

## Q8: TUI framework preference
**Answer:** No preference - recommend based on requirements.

## Q9: Physical location structure
**Answer:** Simple flat list of locations (e.g., "Living Room Shelf 1", "Office")

## Q10: Database format
**Answer:** YAML/TOML files - human-readable and editable.

---

## Summary

A Haskell TUI/CLI application for managing a physical book collection:
- **Full TUI** for browsing/searching with **CLI commands** for quick operations
- **Replace Calibre** - one-time import, then independent management
- **Multiple input sources:** Calibre import, ISBN lookup, manual entry, barcode scanning
- **Full metadata** including custom columns from Calibre
- **YAML/TOML storage** for human-readable data files
- **Simple flat locations** for tracking physical book placement
- **Medium collection** size (500-2000 books)
