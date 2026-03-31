#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/version.sh"

APP_NAME="Litrix"
BUNDLE_ID="com.rooby.Litrix"
APP_VERSION="${LITRIX_APP_VERSION:-1.0-beta1}"
MIN_MACOS_VERSION="14.0"
ICON_SOURCE="litrix3.png"
ICON_FILE="${APP_NAME}.icns"
ICONSET_DIR="${APP_NAME}.iconset"
OUTPUT_ROOT="App"

usage() {
  cat <<EOF
用法:
  ./package_app_arm.sh [-v 版本号] [-o 输出目录]

示例:
  ./package_app_arm.sh
  ./package_app_arm.sh -v 1.0-beta1
  ./package_app_arm.sh -v 1.0beta1 -o ./dist
EOF
}

while getopts ":v:o:h" opt; do
  case "$opt" in
    v) APP_VERSION="$OPTARG" ;;
    o) OUTPUT_ROOT="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    \?)
      echo "错误: 不支持的参数 -$OPTARG"
      usage
      exit 1
      ;;
    :)
      echo "错误: 参数 -$OPTARG 需要一个值"
      usage
      exit 1
      ;;
  esac
done

APP_VERSION="$(echo "$APP_VERSION" | tr -d '[:space:]')"
if [ -z "$APP_VERSION" ]; then
  echo "错误: 版本号不能为空。"
  exit 1
fi

if [ ! -f "Package.swift" ]; then
  echo "错误: 请在 Swift Package 项目根目录执行该脚本。"
  exit 1
fi

APP_BUNDLE_NAME="${APP_NAME}-${APP_VERSION}-arm64.app"
APP_BUNDLE_PATH="${OUTPUT_ROOT}/${APP_BUNDLE_NAME}"
BINARY_PATH=".build/arm64-apple-macosx/release/${APP_NAME}"

echo "1/5 编译 arm64 Release..."
swift build -c release --arch arm64

if [ ! -f "${BINARY_PATH}" ]; then
  echo "错误: 未找到编译产物 ${BINARY_PATH}"
  exit 1
fi

ARCHS="$(lipo -archs "${BINARY_PATH}" 2>/dev/null || true)"
if [ "${ARCHS}" != "arm64" ]; then
  echo "错误: 二进制架构不是纯 arm64，当前架构为: ${ARCHS:-unknown}"
  exit 1
fi

echo "2/5 准备 .app 目录..."
rm -rf "${APP_BUNDLE_PATH}"
mkdir -p "${APP_BUNDLE_PATH}/Contents/MacOS"
mkdir -p "${APP_BUNDLE_PATH}/Contents/Resources"

echo "3/5 写入 Info.plist (版本: ${APP_VERSION})..."
cat <<EOF > "${APP_BUNDLE_PATH}/Contents/Info.plist"
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
    <string>${MIN_MACOS_VERSION}</string>
</dict>
</plist>
EOF

echo "4/5 拷贝可执行文件..."
cp "${BINARY_PATH}" "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"

if [ -f "${ICON_SOURCE}" ] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  echo "   生成应用图标..."
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

  iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE_PATH}/Contents/Resources/${ICON_FILE}"
  rm -rf "${ICONSET_DIR}"
fi

echo "5/5 完成"
echo "输出: ${APP_BUNDLE_PATH}"
echo "架构: arm64"
