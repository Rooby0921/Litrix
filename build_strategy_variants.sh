#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/version.sh"

APP_EXECUTABLE="Litrix"
BASE_BUNDLE_ID="com.rooby.Litrix"
MIN_MACOS_VERSION="14.0"
OUT_DIR="${SCRIPT_DIR}/App/strategy-compare-${LITRIX_APP_VERSION}"
BINARY_PATH="${SCRIPT_DIR}/.build/arm64-apple-macosx/release/${APP_EXECUTABLE}"

mkdir -p "${OUT_DIR}"

ICON_PATH=""
if [ -f "${SCRIPT_DIR}/App/Litrix-${LITRIX_APP_VERSION}-arm64.app/Contents/Resources/Litrix.icns" ]; then
  ICON_PATH="${SCRIPT_DIR}/App/Litrix-${LITRIX_APP_VERSION}-arm64.app/Contents/Resources/Litrix.icns"
fi

build_one() {
  local variant_id="$1"
  local define_flag="$2"
  local display_name="$3"
  local method_note="$4"

  echo "==> Building ${variant_id} (${display_name})"
  if [ -n "${define_flag}" ]; then
    swift build -c release --arch arm64 -Xswiftc "-D${define_flag}"
  else
    swift build -c release --arch arm64
  fi

  if [ ! -f "${BINARY_PATH}" ]; then
    echo "Missing binary: ${BINARY_PATH}" >&2
    exit 1
  fi

  local app_bundle="${OUT_DIR}/Litrix-${LITRIX_APP_VERSION}-${variant_id}.app"
  rm -rf "${app_bundle}"
  mkdir -p "${app_bundle}/Contents/MacOS" "${app_bundle}/Contents/Resources"

  cat > "${app_bundle}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_EXECUTABLE}</string>
    <key>CFBundleIdentifier</key>
    <string>${BASE_BUNDLE_ID}.${variant_id}</string>
    <key>CFBundleName</key>
    <string>${display_name}</string>
    <key>CFBundleDisplayName</key>
    <string>${display_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>Litrix.icns</string>
    <key>CFBundleShortVersionString</key>
    <string>${LITRIX_APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${LITRIX_APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>NSHumanReadableCopyright</key>
    <string>${method_note}</string>
</dict>
</plist>
EOF

  cp "${BINARY_PATH}" "${app_bundle}/Contents/MacOS/${APP_EXECUTABLE}"
  chmod +x "${app_bundle}/Contents/MacOS/${APP_EXECUTABLE}"

  if [ -n "${ICON_PATH}" ] && [ -f "${ICON_PATH}" ]; then
    cp "${ICON_PATH}" "${app_bundle}/Contents/Resources/Litrix.icns"
  fi

  cat > "${app_bundle}/Contents/Resources/BUILD_METHOD.txt" <<EOF
Variant: ${variant_id}
Display Name: ${display_name}
Version: ${LITRIX_APP_VERSION}

Method:
${method_note}
EOF
}

build_one "A-native-toolbar-safearea" "LITRIX_METHOD_A" "Litrix Method A" \
"Method A: native toolbar spacer path + right pane top safe-area extension."

build_one "B-custom-space-topbridge" "LITRIX_METHOD_B" "Litrix Method B" \
"Method B: custom space/flexible-space items + measured top bridge for right pane."

build_one "C-hybrid-space-topbridge" "" "Litrix Method C" \
"Method C: hybrid spacing (native + custom) + measured top bridge for right pane."

cat > "${OUT_DIR}/COMPARE_NOTES.md" <<'EOF'
# Litrix 1.0-beta1 Strategy Compare

- A-native-toolbar-safearea
  - Toolbar: native spacers
  - Right pane: safe-area top extension

- B-custom-space-topbridge
  - Toolbar: custom `Space` + `Flexible Space` items
  - Right pane: explicit top bridge extension

- C-hybrid-space-topbridge
  - Toolbar: native + custom spacing items (stability-first)
  - Right pane: explicit top bridge extension
EOF

echo "Output directory: ${OUT_DIR}"
