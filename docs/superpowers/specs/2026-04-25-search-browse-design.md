# Search and Browse Improvements

Date: 2026-04-25
Status: Approved

## Problem

libri has 449 books but only two ways to find one: scrolling a flat list or using
fuzzy search. The fuzzy search has two problems: it returns too many irrelevant
results (noise from low-similarity partial matches), and it fails on accented
characters (searching "Oscar" does not find "Oscar Contardo"). There is no way to
browse by tag, author, or any other facet -- only a single alphabetical list.

## Solution

Add a command bar for structured filtering and grouped views, and improve the fuzzy
search with accent folding and tighter relevance thresholds. The TUI book list can
reorganise itself into sections (by tag, by author) based on commands typed into the
bar.

## Design

### Command Bar

Pressing `:` in list view opens a command bar at the bottom of the screen. It accepts
structured commands:

| Command              | Effect                                          |
|----------------------|-------------------------------------------------|
| `:tag <name>`        | Filter to books matching that tag               |
| `:author <name>`     | Filter to books matching that author            |
| `:group tag`         | Reorganise list into sections grouped by tag    |
| `:group author`      | Reorganise list into sections grouped by author |
| `:group none`        | Return to flat list                             |
| `:clear`             | Alias for `:group none`, also clears filters    |
| `:sort title`        | Sort by title                                   |
| `:sort author`       | Sort by author                                  |
| `:sort date`         | Sort by date                                    |

Text input uses the same mechanics as the existing search bar: character input,
backspace, Esc to cancel, Enter to execute. Unknown commands show an error in the
status bar.

Tab-completion: pressing Tab after a command keyword (e.g. `:tag `) cycles through
matching completions from the actual collection data. Pressing Tab with an empty
argument shows all available options and cycles through them. Each subsequent Tab
press advances to the next match; the completed text replaces the current argument
in the command bar.

The existing `/` search remains separate. `/` is a quick fuzzy filter; `:` is for
precision commands. They compose: searching with `/` while a filter or group is
active narrows within that view.

### Grouped Views

When `:group tag` is active, the book list renders with section headers:

```
-- Philosophy (82) ------------------------------------------
  Being and Time                    Heidegger
  Critique of Pure Reason           Kant
  ...
-- History (55) ---------------------------------------------
  Rebano                            Contardo
  ...
-- Art (38) -------------------------------------------------
  The Visual Display of...          Tufte
  ...
```

Behaviour:

- Headers are non-selectable. j/k navigation skips over them; the cursor only
  lands on book rows.
- Sections are sorted alphabetically by group name. Books within each section are
  sorted by the current sort field.
- Books with multiple tags appear under each matching tag (no deduplication).
- Books with no tags appear under an "(Untagged)" section at the bottom.
- `:group author` works the same way, grouped by first author. Books with multiple
  authors appear under each.
- The count in parentheses after each header shows the number of books in that
  section.
- The grouped view persists until `:group none` or `:clear`.

### Search Improvements

Two changes to the existing `/` fuzzy search:

Accent folding: before comparing strings, both the query and book fields are
normalised by decomposing Unicode to NFD form and stripping combining diacritical
marks. "Oscar" matches "Óscar", "cafe" matches "café". Combined with the
existing lowercasing in `tokenize`, this means "OSCAR" matches "Óscar Contardo".

Tighter relevance:

- `minTokenMatchThreshold` raised from 0.5 to 0.65, requiring tokens to be more
  similar before counting as a match.
- For single-word queries, require exact substring match or Levenshtein similarity
  >= 0.75 (up from 0.6), cutting noise from unrelated short-token collisions.
- Both thresholds remain configurable via `fuzzyThreshold` in config.yaml.

## Architecture

Four independent units:

### 1. Libri.Text.Normalize (new module)

Pure functions for text normalisation:

- `foldAccents :: Text -> Text` -- NFD decomposition, strip combining marks.
- `normalizeText :: Text -> Text` -- lowercase then foldAccents. Single entry
  point for all comparison-ready text.

Dependencies: `text`, `unicode-transforms`. No IO.

### 2. Libri.TUI.CommandBar (new module)

Command parsing and tab-completion:

- `Command` ADT: `CmdFilterTag Text | CmdFilterAuthor Text | CmdGroup GroupField
  | CmdSort SortField | CmdClear | CmdUnknown Text`
- `parseCommand :: Text -> Command`
- `CommandBarState`: input text, parsed candidates for completion, current
  completion index.
- `completeNext :: CommandBarState -> CommandBarState` -- cycle to next completion.
- `renderCommandBar :: CommandBarState -> Widget Name`

No IO. Pure parsing and state transitions. The candidate list (tags, authors) is
provided by App.hs when the command bar opens.

### 3. Libri.TUI.Views.GroupedList (new module)

Grouped list rendering and navigation:

- `GroupField`: `GroupByTag | GroupByAuthor`
- `ListItem`: `SectionHeader Text Int | BookRow Book`
- `buildGroupedList :: GroupField -> SortField -> SortOrder -> [Book] -> [ListItem]`
- `renderGroupedList :: [ListItem] -> Int -> Widget Name` -- renders items, skips
  headers for selection index.
- `nextSelectableIndex`, `prevSelectableIndex` -- navigation that skips headers.

### 4. Changes to existing modules

Types.hs -- add to AppState:

- `_activeFilter :: Maybe Filter` where `Filter = FilterTag Text | FilterAuthor Text`
- `_groupMode :: Maybe GroupField`

Fuzzy.hs:

- Import and integrate `normalizeText` into `tokenize` (replace `T.toLower` with
  `normalizeText`).
- Raise `minTokenMatchThreshold` from 0.5 to 0.65.
- Single-word query threshold raised to 0.75.

App.hs:

- Add `ViewCommand` to the `View` type, or handle command bar as overlay state
  (similar to how search is handled today).
- Wire `:` keybinding to open command bar.
- On command execution, dispatch to update `_activeFilter`, `_groupMode`,
  `_sortField` in AppState.
- `getVisibleBooks` applies filter before passing to search, then passes result to
  grouped list builder if `_groupMode` is active.
- Tab-completion candidates derived from `_books` at command bar open time.

Widgets/Common.hs:

- Add `commandBarAttr`, `sectionHeaderAttr` to the attribute map.

## Dependencies

New cabal dependency: `unicode-transforms` (for NFD decomposition in accent
folding). Lightweight, pure Haskell, well-maintained.

## Keybinding Changes

The existing `st`/`sa`/`sd` sort keybindings remain as shortcuts. `:sort` is an
alternative for discoverability, not a replacement. The `s` pending-key mechanism
stays unchanged.

## Out of Scope

- CLI filtering flags (`:tag` etc. are TUI-only)
- Location-based filtering (all books currently have null location)
- Persistent filter/group preferences across sessions
- Data enrichment (bulk ISBN lookup, filling missing fields)
- These are future work items in priority order: (b) data enrichment, (c) TUI
  overhaul, (d) new capabilities (lending, statistics, export).
