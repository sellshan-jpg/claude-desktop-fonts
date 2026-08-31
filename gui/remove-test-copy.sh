#!/bin/bash
# 彻底移除测试 Claude：应用副本、它的配置目录，以及它在 clfont 数据目录里的
# 整包备份。正式 Claude 与其备份不受影响。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT="$HOME/Library/Application Support/clfont"
APP="$SUPPORT/Claude-test.app"
CLI="$HERE/clfont"
[ -x "$CLI" ] || CLI="$HOME/.local/bin/clfont"

# 注意：不能用 awk 的字段切分来比对路径——"Application Support" 里有空格，
# $2 只会取到 "/Users/…/Library/Application"，永远匹配不上。整行 grep 再取 pid。
test_pids() {
  ps -axo pid=,comm= | grep -F "$APP/" | awk '{print $1}'
}

echo "▸ 退出正在运行的测试 Claude"
for pid in $(test_pids); do kill "$pid" 2>/dev/null || true; done
# Electron 收到 SIGTERM 未必立刻退，而它只要还活着就会把配置目录重新写回来。
# 必须等它真的消失再删，等不到就强杀。
for _ in $(seq 1 20); do
  [ -z "$(test_pids)" ] && break
  sleep 0.5
done
if [ -n "$(test_pids)" ]; then
  echo "  · 未能正常退出，强制结束"
  for pid in $(test_pids); do kill -9 "$pid" 2>/dev/null || true; done
  sleep 1
fi

if [ -d "$APP" ] && [ -x "$CLI" ]; then
  echo "▸ 删除它的整包备份"
  "$CLI" --app "$APP" backups --purge -y || true
fi

echo "▸ 删除应用副本与配置目录"
for p in "$APP" "$SUPPORT/test-profile" "$SUPPORT/smoke-profile"; do
  if [ -e "$p" ]; then
    rm -rf "$p"
    echo "  · 已删除 $(basename "$p")"
  fi
done

# 目录空了就一并收掉，不留空壳
rmdir "$SUPPORT" 2>/dev/null || true

echo
echo "✓ 测试 Claude 已完全移除。正式 Claude 及其备份未受影响。"
