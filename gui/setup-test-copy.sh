#!/bin/bash
# 重建 clfont 的测试副本，给它一个独立身份，避免和正式 Claude 互相干扰。
#
# 为什么要换身份：测试副本原本是 /Applications/Claude.app 的完整拷贝，
# CFBundleIdentifier 与正式版相同（com.anthropic.claudefordesktop），导致
#   1) 两者被 macOS / Claude 自身视为同一个 app，实例互相打架：
#      装补丁时的冒烟测试启动副本 → 正式版被退出，或副本自己 exit 0 秒退；
#   2) claude:// 登录回调只会落到其中一个（通常是正式版），副本登录不了。
# 对策：改 CFBundleIdentifier + 删掉 CFBundleURLTypes（副本永不抢 claude://）。
# 注意 CFBundleName 必须保持 "Claude"：钥匙串条目 "Claude Safe Storage" 按 app
# 名字派生，改了名字副本就解不开从正式版拷过来的登录态。
set -euo pipefail

SRC="/Applications/Claude.app"
DST="$HOME/Library/Application Support/clfont/Claude-test.app"
PROFILE="$HOME/Library/Application Support/clfont/test-profile"
REAL_PROFILE="$HOME/Library/Application Support/Claude"
NEW_ID="com.anthropic.claudefordesktop.clfonttest"

echo "▸ 退出正在运行的测试副本"
# 整行 grep，不能用 awk 字段比对：DST 路径里有空格
for pid in $(ps -axo pid=,comm= | grep -F "$DST/" | awk '{print $1}'); do
  kill "$pid" 2>/dev/null || true
done
sleep 2

echo "▸ 从正式版复制（APFS clone，秒级）"
mkdir -p "$(dirname "$DST")"
rm -rf "$DST"
ditto "$SRC" "$DST"

echo "▸ 换独立身份"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $NEW_ID" "$DST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$DST/Contents/Info.plist" 2>/dev/null || true
echo "  CFBundleIdentifier → $NEW_ID"
echo "  CFBundleURLTypes   → 已删除（不再抢 claude:// 回调）"
echo "  CFBundleName       → 保持 Claude（钥匙串 Safe Storage 依赖它）"

echo "▸ 重新签名"
# 只改了 Info.plist，破坏的只有顶层封签，嵌套 Helper / Framework 的签名完好，
# 所以不用 --deep——用了反而会把 Helper 的 entitlements 一并抹掉，副本上的
# Cowork、虚拟机等功能会失效，测出来的行为就不再代表正式版了。
# 顶层的 entitlements 照搬原版，只去掉与开发者身份绑定、ad-hoc 下无法生效的项。
ENT="$(mktemp -t clfont-ent)"
if codesign -d --entitlements "$ENT" --xml "$SRC" 2>/dev/null && [ -s "$ENT" ]; then
  for k in com.apple.application-identifier \
           com.apple.developer.team-identifier keychain-access-groups; do
    /usr/libexec/PlistBuddy -c "Delete :$k" "$ENT" >/dev/null 2>&1 || true
  done
  codesign --force --sign - --entitlements "$ENT" "$DST" >/dev/null 2>&1
  echo "  已保留原版 entitlements（去掉身份绑定项）"
else
  codesign --force --sign - "$DST" >/dev/null 2>&1
  echo "  未能读取原版 entitlements，本次不带"
fi
rm -f "$ENT"
codesign -v "$DST" && echo "  ✓ 签名有效"

echo "▸ 播种登录态（只拷认证相关文件，约 10MB，不碰 10G 的 vm_bundles）"
mkdir -p "$PROFILE"
# 刻意不拷 ant-did（Anthropic 设备 ID）：实测共用设备 ID 并不能消掉副本上的
# 「为了安全请重新登录」横幅——服务端的设备绑定还牵涉钥匙串里的设备密钥，而
# 副本的 bundle ID 和签名都变了，本来就凑不齐。既然没效果，就不值得让服务端
# 看到「两个客户端同一台设备」而给正式账号添风险。
# 副本会显示那条横幅，但会话有效、聊天正常加载，不影响预览字体——别去点它。
for f in "Cookies" "Cookies-journal" "Local State" "Preferences" \
         "Local Storage" "Session Storage" "IndexedDB" \
         "buddy-tokens.json"; do
  if [ -e "$REAL_PROFILE/$f" ]; then
    rm -rf "$PROFILE/$f"
    ditto "$REAL_PROFILE/$f" "$PROFILE/$f" 2>/dev/null && echo "  · $f"
  fi
done

echo
echo "✓ 测试副本就绪：$DST"
echo "  启动：\"$DST/Contents/MacOS/Claude\" --user-data-dir=\"$PROFILE\""
echo "  首次启动会弹钥匙串授权（Claude Safe Storage），点「允许」即可沿用登录态。"
