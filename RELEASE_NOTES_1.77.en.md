# Litrix 1.77 Release Notes

Release date: 2026-04-01

## Key Updates

1. Refined the overall interface and information hierarchy for longer reading and matrix-oriented workflows.
2. Advanced Search supports scope locking by `Library`, `Collection`, and `Tag`, and can create a new `Collection` directly from search results.
3. Added `.litrix` archive import and export for backup, migration, and sharing of `settings`, `papers`, and `notes`.
4. The literature matrix now supports hiding columns, moving them left or right, and reordering them.
5. Inline editing is available directly inside the matrix list.
6. Search supports in-text citation format queries.
7. Added `Zombie Collection` to surface long-cold papers and revisit past collection decisions.
8. Added custom keyboard shortcuts for `Tag`.
9. Added toolbar-level API connection status detection.
10. Metadata refresh now splits prompts by target field so only relevant content is sent, reducing token usage.
11. Added toolbar progress display for metadata extraction.
12. Added advanced filtering with a Numbers-inspired interaction model.
13. Improved the right sidebar layout with a pinned title and denser information presentation.
14. Improved Settings with core capabilities including Chinese support.
15. Added built-in Litrix MCP so AI tools can read PDF full text, edit metadata, write notes, and manage collections or tags.
16. Tightened the storage layout: notes are fixed as `note.txt`, and images are stored inside `images/` for more stable reads and writes.
17. Broader performance improvements landed across import/export queueing, indexing, and filter switching.

## Installer

- File: `Litrix-1.77.dmg`
- Architecture: Universal (`arm64` + `x86_64`)

## Note

- `pdf2zh` mentioned in the README is an external terminal integration path, not bundled distribution content.
