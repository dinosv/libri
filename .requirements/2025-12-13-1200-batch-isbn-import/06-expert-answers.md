# Expert Answers - Batch ISBN Import

**Completed:** 2025-12-13

---

## Summary

| Question | Answer |
|----------|--------|
| Q7: Review Interface | Tabla resumen + prompt y/n/select |
| Q8: Info to Show | Metadata completa (ISBN, título, autores, tags, descripción) |
| Q9: Partial Failures | Mostrar éxitos + fallos, permitir importar exitosos |
| Q10: Duplicate Granularity | Mostrar duplicados separados, usuario selecciona |
| Q11: Command Name | `--import-isbn-txt FILE` |

---

## Detailed Answers

### Q7: Review Interface Style
**Selected:** Show table summary, then prompt y/n/select
- Simple CLI-style interaction
- User sees all results before deciding
- Can confirm all, reject all, or select specific ones

### Q8: Information to Show for Review
**Selected:** Full metadata including ISBN, tags, description preview
- User wants complete visibility before importing
- Show: ISBN, title, authors, publisher, year, tags, description (truncated)

### Q9: Handling Partial Failures
**Selected:** Show success + failures, let user import successful ones
- Don't block entire import due to missing ISBNs
- Report which ISBNs failed
- Allow importing the ones that succeeded

### Q10: Duplicate Confirmation Granularity
**Selected:** Show duplicates separately, let user select which to import
- Display duplicates in their own section
- User can choose which duplicates to import (if any)
- More control than global yes/no

### Q11: Command Name
**Selected:** `--import-isbn-txt`
- Custom name chosen by user
- Clear indication it expects a text file with ISBNs
