#!/usr/bin/env bash
# 一键探测 LM Studio 是否可达 + 当前加载的模型列表
# 用法：./scripts/probe-lmstudio.sh [host:port]
set -euo pipefail

HOST="${1:-192.168.1.23:1234}"
URL="http://$HOST/v1/models"

echo "↪ GET $URL"
if ! curl -sS --max-time 5 "$URL" | python3 -m json.tool; then
  echo "❌ 连不上 LM Studio。检查："
  echo "  1) 192.168.1.23 上 LM Studio 已启动 server（Developer → Start Server）"
  echo "  2) LM Studio 设置中 Serve on Local Network 已开"
  echo "  3) 防火墙允许 1234 端口"
  exit 1
fi
