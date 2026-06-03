#!/usr/bin/env bash
# 构建 Focus.app（不签名，仅本机跑）
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "Focus.xcodeproj" ]; then
  echo "Focus.xcodeproj 不存在，先跑 scripts/generate.sh"
  ./scripts/generate.sh
fi

xcodebuild \
  -project Focus.xcodeproj \
  -scheme Focus \
  -configuration Debug \
  -destination 'platform=macOS' \
  build \
  | xcbeautify 2>/dev/null || cat
