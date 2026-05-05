# Litrix Web Importer

This extension reads citation metadata from the current web page and posts it to the local Litrix web import endpoint.

Default endpoint:

```text
http://127.0.0.1:23122/mcp/web-import
```

Install in Chrome or Edge:

1. Open `chrome://extensions`.
2. Enable Developer Mode.
3. Choose `Load unpacked`.
4. Select this `BrowserImporter` folder.
5. Keep Litrix running, open a paper page, then click the Litrix extension button.

Firefox temporary install:

1. Open `about:debugging#/runtime/this-firefox`.
2. Choose `Load Temporary Add-on`.
3. Select `manifest.json` in this folder.

The extension extracts common `citation_*`, Dublin Core, Open Graph, JSON-LD, DOI, keyword, and PDF link metadata. If a PDF link is found, the popup first tries to download the PDF through the browser session and send it to Litrix; if that fails, Litrix falls back to downloading the PDF URL itself.

Safari (macOS):

1. Open `Safari/create-safari-extension.command`.
2. The script uses `safari-web-extension-converter` and `xcodebuild` to generate and build the host app without opening Xcode.
3. Enable `Litrix Safari Importer` in Safari Settings > Extensions.
4. Without an Apple Developer Team ID, enable Safari menu bar > Develop > Allow Unsigned Extensions if Litrix does not appear in the extension list.
