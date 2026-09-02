#!/bin/bash
# 编译 Swift 版 CLI。用法：cli/build.sh [输出路径]，默认 build/clfont-swift
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/clfont-swift}"
mkdir -p "$(dirname "$OUT")"
swiftc -O -swift-version 5 -target arm64-apple-macos26.0 \
  -o "$OUT" "$ROOT"/cli/*.swift
echo "✓ 已编译：$OUT"
