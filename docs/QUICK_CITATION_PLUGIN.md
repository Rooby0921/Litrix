# Quick Citation Plugin Guide (Word / WPS)

Litrix now supports in-app quick citation search:

1. Press `left ⌘ + right ⌘`.
2. Type keywords, press `Enter`.
3. Choose a paper with arrow keys (or mouse).
4. Press `Enter` again to output citation.

Current default output is copied to clipboard.
Direct footnote insertion in Word/WPS requires an external plugin/automation bridge.

## Suggested plugin responsibilities

- Receive citation text from Litrix.
- Insert as footnote at current cursor position in Word/WPS.
- Keep citation format synchronized with `Settings → Citation → Templates` (default APA-7).

## Temporary workflow

Before plugin integration is completed:

1. Trigger quick citation in Litrix.
2. Copy citation result (automatic).
3. Insert into Word/WPS footnote manually.
