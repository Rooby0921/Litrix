#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/version.sh"

APP_NAME="Litrix"
BUNDLE_ID="com.rooby.Litrix"
APP_VERSION="${LITRIX_APP_VERSION:-1.0-beta1}"
DMG_NAME="Litrix-${APP_VERSION}.dmg"
ICON_SOURCE="litrix3.png"
ICON_FILE="${APP_NAME}.icns"
ICONSET_DIR="${APP_NAME}.iconset"

echo "🚀 正在编译通用二进制文件..."
swift build -c release --arch arm64 --arch x86_64

echo "📂 正在构建 ${APP_NAME}.app..."
rm -rf "${APP_NAME}.app"
mkdir -p "${APP_NAME}.app/Contents/MacOS"
mkdir -p "${APP_NAME}.app/Contents/Resources"

echo "📄 正在生成 Info.plist..."
cat <<EOF > "${APP_NAME}.app/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>${ICON_FILE}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.4</string>
</dict>
</plist>
EOF

echo "⚙️ 正在拷贝可执行文件..."
BINARY_PATH=".build/apple/Products/Release/${APP_NAME}"
if [ ! -f "${BINARY_PATH}" ]; then
  BINARY_PATH=$(find .build -type f -name "${APP_NAME}" | grep -E '/(release|Release)/' | head -n 1 || true)
fi
if [ -z "${BINARY_PATH}" ]; then
  echo "❌ 错误：找不到 ${APP_NAME} 的 Release 编译产物。"
  exit 1
fi
cp "${BINARY_PATH}" "${APP_NAME}.app/Contents/MacOS/"
chmod +x "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

if [ -f "${ICON_SOURCE}" ] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  echo "🎨 正在生成应用图标..."
  rm -rf "${ICONSET_DIR}"
  mkdir -p "${ICONSET_DIR}"

  sips -z 16 16 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "${ICONSET_DIR}" -o "${APP_NAME}.app/Contents/Resources/${ICON_FILE}"
  rm -rf "${ICONSET_DIR}"
fi

echo "▶️ 正在启动 ${APP_NAME}.app..."
open "./${APP_NAME}.app"

if command -v create-dmg >/dev/null 2>&1; then
  echo "💿 正在生成 DMG 安装包..."
  rm -f "${DMG_NAME}"

  create-dmg \
    --volname "${APP_NAME} Installer" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 175 120 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 425 120 \
    "${DMG_NAME}" \
    "./${APP_NAME}.app"

  echo "✅ 打包完成：${DMG_NAME}"
else
  echo "ℹ️ 未安装 create-dmg，已跳过 DMG 生成。"
  echo "✅ ${APP_NAME}.app 已构建并启动。"
fi
