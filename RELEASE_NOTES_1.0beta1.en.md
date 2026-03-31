# Litrix 1.0beta1 Release Notes

Release date: 2026-03-26

## Key Updates (P1-P15)

1. (P1) Refined the overall UI design with clearer hierarchy and more consistent visual structure.
2. (P2) Advanced Search now supports scope locking by `Library`, `Collection`, and `Tag`, and can create a new `Collection` directly from search results.
3. (P3) Added custom `.litrix` archive-based data workflow (corresponding to the `.litirx` wording you mentioned): you can back up core data including `settings`, `papers`, and `notes`, and import from other matrix libraries.
4. (P4) Added support for hiding columns and moving columns left/right.
5. (P5) You can now edit entries directly in the literature matrix list.
6. (P6) Search now supports in-text citation format queries.
7. (P7) Added `Zombie Collection`: a practical way to surface long-cold papers, clean storage, and revisit past collecting decisions.
8. (P8) Added custom keyboard shortcuts for `Tag` actions.
9. (P9) Added toolbar-level API connection status detection.
10. (P10-P11) Metadata refresh now supports custom field-type updates, and prompt splitting by target field so only relevant prompts are sent, reducing token usage.
11. (P12) Added metadata extraction progress display in the toolbar.
12. (P13) Added advanced filtering with a Numbers-inspired interaction style.
13. (P14) Optimized right sidebar layout with a pinned top title, reducing wasted space and increasing information density.
14. (P15) Improved Settings with core capabilities including Chinese language support and dark mode.
15. Broader performance improvements across import/export (with queueing), `Collection`/`Tag` switching, and indexing logic, resulting in noticeably less stutter.

## Other Improvements

- Updated the app icon. It is still evolving, but this version is more durable visually than the first one, and the black style feels more premium.

## Installer

- File: `Litrix-1.0beta1.dmg`
- Architecture: Universal (`arm64` + `x86_64`)
- SHA256: `d78ae020c4891f05a57978b08c173593fbfb0b1e695610e895cae69cafbe3b02`

We are getting closer, step by step, to the 1.0 vision.
