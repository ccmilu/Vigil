#!/usr/bin/env bash
# 构建 Vigil.app（不签名，仅本机跑）
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "Vigil.xcodeproj" ]; then
  echo "Vigil.xcodeproj 不存在，先跑 scripts/generate.sh"
  ./scripts/generate.sh
fi

xcodebuild \
  -project Vigil.xcodeproj \
  -scheme Vigil \
  -configuration Debug \
  -destination 'platform=macOS' \
  build \
  | xcbeautify 2>/dev/null || cat
