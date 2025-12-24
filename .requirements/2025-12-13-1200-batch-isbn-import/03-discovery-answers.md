# Discovery Answers - Batch ISBN Import

**Completed:** 2025-12-13

---

## Summary of Requirements

| Question | Answer |
|----------|--------|
| Q1: File Format | Un ISBN por línea (texto simple) |
| Q2: Invalid ISBNs | Saltar, reportar al final, revisar antes de guardar |
| Q3: Duplicates | Advertir pero permitir importar si usuario lo desea |
| Q4: Rate Limiting | Delay automático 1-2 seg entre peticiones |
| Q5: Progress | Verbose - mostrar progreso por cada libro |
| Q6: Interface | Solo CLI |

---

## Detailed Answers

### Q1: File Format
**Selected:** One ISBN per line (simple text file)
- Easiest to create and edit
- User can simply copy/paste ISBN list

### Q2: Invalid ISBN Handling
**Selected:** Skip and continue, report at end
**Additional requirements:**
- Show list of ISBNs not found at the end
- **IMPORTANT:** Allow user to review/verify fetched records BEFORE saving to database
- Two-phase process: fetch → review → confirm → save

### Q3: Duplicate Handling
**Selected:** Warn about duplicates + option to import anyway
- Show warning when ISBN already exists in collection
- Give user choice to skip or import as duplicate

### Q4: Rate Limiting
**Selected:** Automatic delay (1-2 seconds)
- Respect OpenLibrary API limits
- Built-in delay, no user configuration needed

### Q5: Progress Feedback
**Selected:** Verbose progress per book
- Show each ISBN being processed
- Show success/failure for each
- Final summary at end

### Q6: Interface
**Selected:** CLI only
- Command: `libri --import-batch <file>`
- Batch operations suit CLI better than TUI
