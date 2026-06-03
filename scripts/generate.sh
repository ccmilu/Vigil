#!/usr/bin/env bash
# 用 XcodeGen 从 Project.yml 重新生成 Focus.xcodeproj
# 改了 Project.yml、加了新文件 / 新 target，都要跑一下这个脚本
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ 未找到 xcodegen，请先 brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
echo "✅ Focus.xcodeproj 已生成 / 更新"
