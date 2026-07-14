# Tag sidebar for the libri TUI

Date: 2026-07-14
Status: approved

## Goal

Tags are the primary browsing axis of the collection (449 books, genre
categories such as Filosofía, Historia, Arte), but reaching them today
requires typed commands (`:group tag`, `:tag X`). Add a persistent tag
sidebar so a tag filter is always one or two keystrokes away.

## Layout

Three panes: `[Tags | Books | Details]`. The sidebar is a fixed-width
(~22 column) left pane containing:

1. `All (N)` — first entry; selecting it clears the tag filter.
2. Every distinct tag, alphabetically ordered with accents folded via
   the existing `normalizeText` (Filosofía sorts under F). Each shows
   its book count.
3. `(Untagged) (N)` — last entry; selecting it filters to books with
   no tags.

Counts are computed from the full collection (not the current filter)
and recomputed whenever the book list reloads (refresh, save, delete,
move).

## Interaction

- Tab switches focus between the book list and the sidebar. The
  focused pane shows the `>` selection marker.
- Sidebar focused: `j`/`k`/arrow keys move; Enter applies the selected
  entry as the active filter and returns focus to the book list; Esc
  returns focus without changing anything.
- The entry corresponding to the active filter stays highlighted.
- Search, sorting and grouping compose with the tag filter exactly as
  filters compose today (`getVisibleBooks` pipeline unchanged).

## Filter semantics

The existing `:tag X` command filters by normalised substring, so
"Arte" would also match "Arte moderno". The sidebar must filter by
exact tag. Add a constructor to `Filter`:

- `FilterTagExact Text` — matches books where any tag is
  normalised-equal to the value.
- `FilterUntagged` — matches books with no tags (backs the
  `(Untagged)` entry).

The command bar keeps its substring behaviour (`FilterTag`).

## Components

- `Libri.TUI.Views.TagSidebar` (new module)
  - `data TagEntry = AllBooks Int | TagEntry Text Int | Untagged Int`
  - `buildTagEntries :: [Book] -> [TagEntry]` — pure: distinct tags,
    accent-folded alphabetical order, counts, All first, Untagged last
    (Untagged omitted when every book has tags).
  - `renderTagSidebar :: [TagEntry] -> Int -> Bool -> Maybe Filter -> Widget Name`
    — selection index, focus flag, active filter for highlighting.
  - `entryToFilter :: TagEntry -> Maybe Filter` — All maps to Nothing.
- `Libri.Types` — add `FilterTagExact` and `FilterUntagged` to
  `Filter`.
- `Libri.TUI.App`
  - `TUIState` gains `tuiSidebarFocus :: Bool` and
    `tuiTagIndex :: Int`.
  - `applyFilter` handles the new constructors.
  - Tab/focus handling and sidebar key handling in the list view.
  - `mainLayout` becomes three panes; `filterIndicator` shows the new
    filter kinds.

No new dependencies, no storage changes, no CLI changes.

## Edge cases

- Empty library: sidebar shows `All (0)` only; Enter is a no-op filter
  clear.
- Tag list changes under the cursor (delete/edit removes the last book
  with a tag): clamp `tuiTagIndex` to the rebuilt entry list.
- Terminal too narrow: panes shrink proportionally; no special
  handling in v1.

## Testing

- `TagSidebarSpec`: counts, accent-folded ordering, All/Untagged
  placement, Untagged omitted when all books tagged, empty library,
  entryToFilter mapping.
- Filter tests: `FilterTagExact` does not match supersets
  ("Arte" vs "Arte moderno"), matches accent-insensitively;
  `FilterUntagged` matches only tagless books.
- End-to-end: drive the TUI in tmux (per `.claude/skills/verify`),
  Tab into sidebar, filter by tag, verify book list and indicator.

## Out of scope (later design cycles)

Richer list columns, scrollable details pane, bulk actions
(multi-select tag/move/rate), sidebar visibility toggle, count-order
toggle, multi-tag filtering.
