#!/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/package_app_arm_to_application.sh"

if [ ! -x "${TARGET_SCRIPT}" ]; then
  echo "错误: 未找到可执行脚本 ${TARGET_SCRIPT}"
  echo
  read -n 1 -s -r -p "按任意键退出..."
  echo
  exit 1
fi

cd "${SCRIPT_DIR}" || exit 1

echo "启动封装脚本:"
echo "  ${TARGET_SCRIPT}"
echo

"${TARGET_SCRIPT}" "$@"
STATUS=$?

echo
if [ "${STATUS}" -eq 0 ]; then
  echo "封装脚本执行完成。"
else
  echo "封装脚本执行失败，退出码: ${STATUS}"
fi
echo
read -n 1 -s -r -p "按任意键退出..."
echo
exit "${STATUS}"
