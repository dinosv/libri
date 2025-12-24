# Discovery Questions

Generated: 2025-12-11T20:30:00Z

## Q1: What is the primary use case?
```
What will you mainly use this tool for?

1. Browse and search your physical book collection [default - most common need]
2. Track reading status and progress
3. Manage book locations (shelves, rooms, lent books)
4. All of the above
5. Other (please specify)
```

## Q2: How do you want to interact with the tool?
```
What kind of interface do you prefer?

1. Full TUI with panels, navigation, and real-time updates [default - rich experience]
2. CLI commands with pretty output (like git)
3. Hybrid: CLI commands that can launch TUI views
4. Other (please specify)
```

## Q3: What Calibre data matters most?
```
Calibre stores: title, authors, series, tags, publisher, date, rating, comments, custom columns, and more. Which metadata is most important for your physical collection?

1. Core fields: title, authors, series, tags [default - essential metadata]
2. Full metadata including custom columns
3. Minimal: just title and authors
4. Other (please specify)
```

## Q4: Do you need to track physical-specific info?
```
Physical books have info that ebooks don't. What do you need to track?

1. Location only (which shelf/room) [default - most useful for physical]
2. Location + condition + purchase info
3. Location + lending history (who borrowed what)
4. I'll use Calibre's custom columns for this
5. Other (please specify)
```

## Q5: Should changes sync back to Calibre?
```
When you update data in this tool, should it modify the Calibre database?

1. Read-only - never modify Calibre DB [default - safest approach]
2. Two-way sync - changes update Calibre
3. One-way import - copy data to separate DB, then manage independently
4. Other (please specify)
```

## Q6: What's the expected collection size?
```
Approximately how many books are in your collection?

1. Small (under 500 books) [default]
2. Medium (500-2000 books)
3. Large (2000-10000 books)
4. Very large (10000+ books)
```

## Q7: What programming language do you prefer?
```
Which language should the tool be built in?

1. Python (rich ecosystem: Textual, Rich, Click) [default - best TUI support]
2. Rust (fast, modern: ratatui)
3. Go (simple, fast: bubbletea)
4. Other (please specify)
```
