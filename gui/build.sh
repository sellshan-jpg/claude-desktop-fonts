#!/bin/bash
# 编译 GUI、生成图标、组 bundle、ad-hoc 签名。
# 用法：gui/build.sh [输出路径]   默认 build/Clfont.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/gui/ClfontApp.swift"
OUT="${1:-$ROOT/build/Clfont.app}"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

swiftc -swift-version 5 -O -parse-as-library \
  -target arm64-apple-macos26.0 \
  -o "$OUT/Contents/MacOS/clfont-gui" "$SRC"

# CLI 编进 bundle。Swift 版对 Xcode 命令行工具零依赖——它只调用 codesign /
# ditto / du / ps，四个都是系统自带的真二进制；而 python3 是 CLT 的转发壳，
# 那正是这次重写要消灭的前置条件。
swiftc -O -swift-version 5 -target arm64-apple-macos26.0 \
  -o "$OUT/Contents/Resources/clfont" "$ROOT"/cli/*.swift
chmod +x "$OUT/Contents/Resources/clfont"
for sh in setup-test-copy remove-test-copy; do
  cp "$ROOT/gui/$sh.sh" "$OUT/Contents/Resources/$sh.sh"
  chmod +x "$OUT/Contents/Resources/$sh.sh"
done

# 图标：满画布不透明出稿（见 render-icon.swift 顶部注释），系统负责圆角
ICONSET="$(mktemp -d)/Clfont.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/gui/render-icon.swift" "$ICONSET/src" >/dev/null
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
            "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
  set -- $pair
  cp "$ICONSET/src/Clfont-icon-$1.png" "$ICONSET/icon_$2.png"
done
rm -rf "$ICONSET/src"
iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/Clfont.icns"

cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clfont</string>
  <key>CFBundleDisplayName</key><string>Clfont</string>
  <key>CFBundleIdentifier</key><string>local.clfont.gui</string>
  <key>CFBundleExecutable</key><string>clfont-gui</string>
  <key>CFBundleIconFile</key><string>Clfont</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>6.0</string>
  <key>CFBundleVersion</key><string>9</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$OUT" >/dev/null 2>&1
codesign -v "$OUT" && echo "✓ 构建并签名完成：$OUT"
