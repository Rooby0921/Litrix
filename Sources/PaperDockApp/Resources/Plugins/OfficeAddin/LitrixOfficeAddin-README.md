# Litrix Office Add-in

This package contains a local Office task pane add-in for Litrix citations.

The task pane connects to the Litrix MCP endpoint:

```text
http://127.0.0.1:23122/mcp
```

It can search the Litrix library with `search_library`, format the selected item, and insert the citation as inline text, a footnote, or an endnote.

Install outline:

1. Keep Litrix running.
2. Run `start-local-server.command` from this folder.
3. Sideload `word/LitrixWordManifest.xml` in Microsoft Word.
4. Open the Litrix ribbon group, then use `引文格式` or `引用格式`.

WPS note:
- Office Web Add-in compatibility on WPS for macOS is limited.
- For macOS, use `Plugins/WPSMacBridge` as the recommended insertion workflow.
