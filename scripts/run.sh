#!/usr/bin/env bash
# 构建并启动 Vigil.app（命令行方式，不用 Xcode）
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

# 找出 build 产物路径
APP_PATH=$(
  xcodebuild -project Vigil.xcodeproj -scheme Vigil -configuration Debug \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}' | head -1
)
APP="$APP_PATH/Vigil.app"

if [ ! -d "$APP" ]; then
  echo "❌ 未找到 $APP" >&2
  exit 1
fi

echo "🚀 启动 $APP"
open "$APP"
