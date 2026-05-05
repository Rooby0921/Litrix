#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

source "${SCRIPT_DIR}/version.sh"

APP_NAME="Litrix"
APP_VERSION="${LITRIX_APP_VERSION:-1.77}"
OUTPUT_ROOT="App"
APPLICATION_PATH="/Applications/${APP_NAME}.app"

usage() {
  cat <<EOF
用法:
  ./package_app_arm_to_application.sh [-v 版本号]

示例:
  ./package_app_arm_to_application.sh
  ./package_app_arm_to_application.sh -v 1.81beta

说明:
  该脚本会先调用 ./package_app_arm.sh 封装 arm64 应用，
  然后将生成的 Litrix-版本-arm64.app 替换为 /Applications/Litrix.app。
EOF
}

while getopts ":v:h" opt; do
  case "$opt" in
    v) APP_VERSION="$OPTARG" ;;
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

APP_VERSION="$(echo "${APP_VERSION}" | tr -d '[:space:]')"
if [ -z "${APP_VERSION}" ]; then
  echo "错误: 版本号不能为空。"
  exit 1
fi

if [ ! -x "${SCRIPT_DIR}/package_app_arm.sh" ]; then
  echo "错误: 未找到可执行脚本 ${SCRIPT_DIR}/package_app_arm.sh"
  exit 1
fi

BUILT_APP_PATH="${OUTPUT_ROOT}/${APP_NAME}-${APP_VERSION}-arm64.app"

echo "1/3 封装 ${APP_NAME} ${APP_VERSION} arm64..."
"${SCRIPT_DIR}/package_app_arm.sh" -v "${APP_VERSION}" -o "${OUTPUT_ROOT}"

if [ ! -d "${BUILT_APP_PATH}" ]; then
  echo "错误: 未找到封装产物 ${BUILT_APP_PATH}"
  exit 1
fi

if [ ! -f "${BUILT_APP_PATH}/Contents/MacOS/${APP_NAME}" ]; then
  echo "错误: ${BUILT_APP_PATH} 缺少可执行文件 Contents/MacOS/${APP_NAME}"
  exit 1
fi

ARCHS="$(lipo -archs "${BUILT_APP_PATH}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true)"
if [ "${ARCHS}" != "arm64" ]; then
  echo "错误: 应用二进制架构不是纯 arm64，当前架构为: ${ARCHS:-unknown}"
  exit 1
fi

echo "2/3 替换 ${APPLICATION_PATH}..."
rm -rf "${APPLICATION_PATH}"
ditto "${BUILT_APP_PATH}" "${APPLICATION_PATH}"

INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${APPLICATION_PATH}/Contents/Info.plist")"
INSTALLED_ARCHS="$(lipo -archs "${APPLICATION_PATH}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true)"

echo "3/3 完成"
echo "已安装: ${APPLICATION_PATH}"
echo "版本: ${INSTALLED_VERSION}"
echo "架构: ${INSTALLED_ARCHS}"
