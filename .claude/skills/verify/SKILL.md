---
name: verify
description: Build, launch and drive libri (CLI + Brick TUI) against a scratch data directory to verify changes end-to-end.
---

# Verifying libri

## Build and locate the binary

```bash
cabal build
LIBRI=$(cabal list-bin libri)
```

## Scratch environment

libri reads a YAML config (`-c PATH`) whose `dataDir` holds `books/*.yaml`
plus `locations.yaml`. Never point it at the real collection, which lives
outside this repo (see `dataDir` in `~/.config/libri/config.yaml`).

```bash
SCRATCH=$(mktemp -d)
mkdir -p "$SCRATCH/data/books"
cat > "$SCRATCH/config.yaml" <<EOF
dataDir: $SCRATCH/data
defaultLocation: null
isbnApi: openlibrary
fuzzyThreshold: 0.6
EOF
```

Seed a book by writing a YAML file into `$SCRATCH/data/books/` (fields: id,
isbn, title, authors, series, seriesIndex, publisher, published, tags,
rating, comments, location, custom, added, modified — timestamps ISO 8601).

## CLI flows

```bash
"$LIBRI" -c "$SCRATCH/config.yaml" --list
"$LIBRI" -c "$SCRATCH/config.yaml" --search QUERY
"$LIBRI" -c "$SCRATCH/config.yaml" --show ID_OR_ISBN
echo y | "$LIBRI" -c "$SCRATCH/config.yaml" --delete ID   # asks y/N
"$LIBRI" -c "$SCRATCH/config.yaml" --add --isbn ISBN      # needs network
```

## TUI (Brick)

Drive it in a tmux pane. Gotcha: `tmux-cli send` did not reliably deliver
Enter to Brick — use raw `tmux send-keys` for special keys instead:

```bash
tmux-cli launch "zsh"           # gives PANE like remote-cli-session:1
tmux send-keys -t PANE "$LIBRI -c $SCRATCH/config.yaml" Enter
tmux send-keys -t PANE e        # keys: a add, e edit, d delete, / search, : cmd
tmux send-keys -t PANE Tab      # next form field; Enter saves; Escape cancels
tmux capture-pane -t PANE -p    # evidence
tmux kill-session -t remote-cli-session
```

After TUI edits, inspect the YAML in `$SCRATCH/data/books/` to confirm what
was persisted (watch for `.tmp` leftovers — there should be none).
