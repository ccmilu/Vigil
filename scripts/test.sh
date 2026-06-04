#!/usr/bin/env bash
# 跑单元测试
#   ./scripts/test.sh                 仅单元测试（mock）
#   ./scripts/test.sh --integration   也跑集成测试（连真实 LM Studio）
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "Vigil.xcodeproj" ]; then
  ./scripts/generate.sh
fi

ENV_PREFIX=""
if [ "${1:-}" = "--integration" ]; then
  echo "↪ 集成测试将访问 LM Studio（DemoConfig.baseURL）"
  ENV_PREFIX="RUN_INTEGRATION=1"
fi

# shellcheck disable=SC2086
env $ENV_PREFIX xcodebuild \
  -project Vigil.xcodeproj \
  -scheme Vigil \
  -destination 'platform=macOS' \
  test \
  | xcbeautify 2>/dev/null || cat
