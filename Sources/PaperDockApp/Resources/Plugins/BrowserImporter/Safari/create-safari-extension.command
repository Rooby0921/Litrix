#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUPPORT_ROOT="${HOME}/Library/Application Support/Litrix/SafariWebImporter"
PROJECT_ROOT="${SUPPORT_ROOT}/Generated-Safari-App"
DERIVED_DATA="${SUPPORT_ROOT}/DerivedData"
BUILD_LOG="${SUPPORT_ROOT}/xcodebuild.log"
INSTALL_ROOT="${HOME}/Applications"
APP_NAME="Litrix Safari Importer"
BUNDLE_PREFIX="com.rooby.Litrix"
APP_BUNDLE_ID="com.rooby.Litrix.SafariImporter"
EXTENSION_BUNDLE_ID="com.rooby.Litrix.SafariImporter.Extension"
EXTENSION_VERSION="1.3.0"
INSTALLED_APP_PATH="${INSTALL_ROOT}/${APP_NAME}.app"
LEGACY_INSTALLED_APP_PATH="${SUPPORT_ROOT}/${APP_NAME}.app"

echo "Litrix Safari 插件安装器"
echo "插件源目录：${EXT_ROOT}"
echo "输出目录：${SUPPORT_ROOT}"
echo "安装位置：${INSTALLED_APP_PATH}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "未找到 xcrun。请先安装完整 Xcode。"
  exit 1
fi

if ! xcrun --find safari-web-extension-converter >/dev/null 2>&1; then
  echo "未找到 safari-web-extension-converter。请安装或更新完整 Xcode。"
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "未找到 xcodebuild。请先安装完整 Xcode。"
  exit 1
fi

mkdir -p "$SUPPORT_ROOT" "$INSTALL_ROOT"
rm -rf "$PROJECT_ROOT"
mkdir -p "$PROJECT_ROOT"

echo "正在生成 Safari Web Extension 工程..."
xcrun safari-web-extension-converter "$EXT_ROOT" \
  --project-location "$PROJECT_ROOT" \
  --app-name "$APP_NAME" \
  --bundle-identifier "$BUNDLE_PREFIX" \
  --macos-only \
  --swift \
  --copy-resources \
  --force \
  --no-prompt \
  --no-open

PROJECT_FILE="$(find "$PROJECT_ROOT" -maxdepth 3 -name "*.xcodeproj" | head -n 1)"
if [[ -z "$PROJECT_FILE" ]]; then
  echo "未能生成 Xcode 工程。"
  open "$PROJECT_ROOT"
  exit 1
fi

PBXPROJ="${PROJECT_FILE}/project.pbxproj"
VIEW_CONTROLLER="${PROJECT_ROOT}/${APP_NAME}/${APP_NAME}/ViewController.swift"

if [[ -f "$PBXPROJ" ]]; then
  /usr/bin/perl -0pi -e 's/PRODUCT_BUNDLE_IDENTIFIER = "?com\.rooby\.Litrix(?:\.Litrix-Safari-Importer|-Safari-Importer)"?;/PRODUCT_BUNDLE_IDENTIFIER = com.rooby.Litrix.SafariImporter;/g; s/PRODUCT_BUNDLE_IDENTIFIER = com\.rooby\.Litrix(?:\.SafariImporter)?\.Extension;/PRODUCT_BUNDLE_IDENTIFIER = com.rooby.Litrix.SafariImporter.Extension;/g' "$PBXPROJ"
  /usr/bin/perl -0pi -e 's/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = 1.3.0;/g; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = 4;/g' "$PBXPROJ"
fi

if [[ -f "$VIEW_CONTROLLER" ]]; then
  /usr/bin/perl -0pi -e 's/let extensionBundleIdentifier = ".*?"/let extensionBundleIdentifier = "com.rooby.Litrix.SafariImporter.Extension"/g' "$VIEW_CONTROLLER"
  /usr/bin/perl -0pi -e 'if (!/litrixOpenSafariExtensionPreferences/) { s/(\n\s*override func viewDidLoad\(\) \{\n\s*super\.viewDidLoad\(\)\n)/$1\n        litrixOpenSafariExtensionPreferences(after: 0.8)\n/s; s/(\n\s*func webView\(_ webView: WKWebView, didFinish navigation: WKNavigation!\) \{)/\n    private func litrixOpenSafariExtensionPreferences(after delay: TimeInterval = 0.0) {\n        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {\n            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { _ in }\n        }\n    }\n$1/s }' "$VIEW_CONTROLLER"
fi

echo "正在命令行编译宿主 App（本机签名，不打开 Xcode 界面）..."
if ! xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM="" \
  build >"$BUILD_LOG" 2>&1; then
  echo "命令行编译失败，已打开生成工程。"
  echo "日志位置：${BUILD_LOG}"
  tail -n 80 "$BUILD_LOG" || true
  open "$PROJECT_FILE"
  exit 2
fi

APP_PATH="$(find "${DERIVED_DATA}/Build/Products/Debug" -maxdepth 2 -name "${APP_NAME}.app" | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "编译完成，但没有找到宿主 App。"
  echo "日志位置：${BUILD_LOG}"
  open "$PROJECT_FILE"
  exit 3
fi

rm -rf "$INSTALLED_APP_PATH"
/usr/bin/ditto "$APP_PATH" "$INSTALLED_APP_PATH"
/usr/bin/xattr -dr com.apple.quarantine "$INSTALLED_APP_PATH" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$INSTALLED_APP_PATH" >/dev/null 2>&1 || true
APPEX_PATH="$(find "${INSTALLED_APP_PATH}/Contents/PlugIns" -maxdepth 1 -name "*.appex" | head -n 1)"
if [[ -n "$APPEX_PATH" ]]; then
  /usr/bin/pluginkit -m -A -D -v -i "$EXTENSION_BUNDLE_ID" 2>/dev/null \
    | /usr/bin/awk -F '\t' '/\.appex$/ {print $NF}' \
    | while IFS= read -r OLD_APPEX_PATH; do
        if [[ -n "$OLD_APPEX_PATH" && "$OLD_APPEX_PATH" == *"Litrix Safari Importer Extension.appex" && "$OLD_APPEX_PATH" != "$APPEX_PATH" ]]; then
          /usr/bin/pluginkit -r "$OLD_APPEX_PATH" >/dev/null 2>&1 || true
        fi
      done
  /usr/bin/pluginkit -a "$APPEX_PATH" >/dev/null 2>&1 || true
fi

if [[ "$LEGACY_INSTALLED_APP_PATH" != "$INSTALLED_APP_PATH" ]]; then
  rm -rf "$LEGACY_INSTALLED_APP_PATH"
fi

if [[ "${LITRIX_SAFARI_INSTALLER_NO_OPEN:-0}" != "1" ]]; then
  open "$INSTALLED_APP_PATH"
  open -a Safari >/dev/null 2>&1 || true
  echo "Safari 插件宿主 App 已生成并打开：${INSTALLED_APP_PATH}"
else
  echo "Safari 插件宿主 App 已生成：${INSTALLED_APP_PATH}"
fi

echo "下一步：在 Safari 设置 > 扩展 中启用 Litrix Safari Importer。"
echo "如果 Safari 扩展列表中仍然没有 Litrix：请先彻底退出并重新打开 Safari，再重新运行本安装器。"
