#!/bin/zsh
set -euo pipefail

if [ -z "$(pbpaste | tr -d '[:space:]')" ]; then
  osascript -e 'display alert "剪贴板为空" message "请先在 Litrix 中复制快速引用。" as warning'
  exit 1
fi

osascript <<'APPLESCRIPT'
tell application "System Events"
  keystroke "f" using {command down, option down}
  delay 0.12
  keystroke "v" using {command down}
end tell
APPLESCRIPT
