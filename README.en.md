[简体中文](./README.md) | English

# Litrix

Litrix is a native macOS literature matrix tool for researchers, graduate students, and students who work with papers over the long term. It is designed around importing, organizing, reading, annotating, filtering, exporting, and collaborating with AI so that repetitive work stays low and attention can return to notes, comparison, and judgment.

## Version

- Current version: `1.77`
- Platform: macOS 14+
- Stack: SwiftUI + Swift 6.2
- Distribution: source repository + macOS `.dmg` installer

## What Litrix 1.77 Can Do

### Ingestion and Library Building

- Import PDFs and organize them into a local `Papers` directory
- Import BibTeX
- Fetch metadata from Crossref by DOI
- Enrich and refresh metadata from PDF text with AI
- Import and export `.litrix` archives for backup, migration, and sharing literature matrices

### Literature Matrix and Reading Workflow

- Native macOS three-column interface
- Inline editing directly in the literature matrix
- Hide columns, move them left or right, and reorder them
- Advanced search and advanced filtering
- In-text citation format search
- Multiple management views including `Collection`, `Tag`, and `Zombie Collection`
- Collections, tags, ratings, image attachments, and plain-text notes
- Hover an image and press Space to preview it
- Quick Look preview, open in default app, and reveal files in Finder

### AI and Automation

- SiliconFlow and DashScope support
- Prompt splitting by target metadata field to reduce wasted token usage
- Toolbar-level API connection status
- Toolbar progress display for metadata extraction
- Built-in Litrix MCP for AI-driven library search, PDF full-text reading, metadata editing, note writing, and collection/tag management

### Storage and Export

- Automatic `library.json` persistence with backup history
- Notes stored as fixed `note.txt`, with images kept inside `images/`
- Export BibTeX, detailed Markdown summaries, and attachments
- Local-first storage with explicit, inspectable directories

## Screenshots

### Search and Matrix Fields

![Search and Matrix Fields](docs/images/search-more-fields.png)

### Litrix MCP

![Litrix MCP](docs/images/mcp-support.png)

### pdf2zh Terminal Integration

Litrix does not bundle `pdf2zh` directly. Instead, it provides a terminal-based integration path so you can trigger double-page translation workflows after installing `pdf2zh` on your own machine.

![pdf2zh Terminal Integration](docs/images/pdf2zh-terminal-support.png)

### Task Progress Display

![Task Progress Display](docs/images/progress-indicator.png)

### Image Preview

![Image Preview](docs/images/image-preview.png)

## Requirements

- macOS 14 or later
- Xcode 26.3+ or Swift 6.2+
- An API key is required only for AI metadata enrichment

This repository has been checked locally with `Swift 6.2.4` and `Xcode 26.3`.

## Quick Start

### Clone

```bash
git clone https://github.com/Rooby0921/Litrix.git
cd Litrix
```

### Build and Run

```bash
swift build
swift run Litrix
```

You can also open the Swift Package directly in Xcode and run it there.

## Package the App

The repository already includes `.app` and `.dmg` packaging scripts:

```bash
chmod +x package_app_arm.sh build_dmg.sh publish.sh
./publish.sh
```

If you only want the Apple Silicon build:

```bash
./package_app_arm.sh -v 1.77 -o ./dist
```

## Prepare pdf2zh in Terminal

Litrix only provides the terminal entry point. It does not bundle the third-party translation tool itself. Install `pdf2zh` locally first, then call the workflow from Litrix.

Example:

```bash
pip install pdf2zh
pdf2zh --help
```

## Data Locations

- App settings and library data: `~/Library/Application Support/Litrix/`
- Default paper directory: `~/Litrix/Papers/`
- Backup directory: `~/Library/Application Support/Litrix/Backups/`

The paper directory can be changed in Settings. The current storage layout is documented in [docs/storage-layout.md](./docs/storage-layout.md).

## Repository Layout

- `Sources/PaperDockApp/`: main application source
- `docs/storage-layout.md`: current data structure documentation
- `package_app_arm.sh` / `build_dmg.sh` / `publish.sh`: packaging scripts
- `ApiCallTest/`: API test scripts

## Notes

- The repository does not commit `.app`, `.dmg`, build caches, or local test paper PDFs
- `pdf2zh` shown in the README is an external integration path, not bundled distribution content
