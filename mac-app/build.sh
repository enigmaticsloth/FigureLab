#!/bin/bash
# Builds FigureLab.app from main.swift plus the editor HTML.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HTML="$HERE/../figure-editor.html"
OUT="${1:-$HERE/../FigureLab.app}"
NAME="FigureLab"

[ -f "$HTML" ] || { echo "找不到 $HTML"; exit 1; }

echo "==> 清除舊版本"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

echo "==> 建立圖示"
ICONSET="$HERE/icon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512; do
  sips -z $s $s "$HERE/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d "$HERE/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
cp "$HERE/icon-1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> 編譯 (universal: arm64 + x86_64)"
swiftc -O \
  -target arm64-apple-macos11.0 \
  -o "$HERE/.bin-arm64" "$HERE/main.swift"
if swiftc -O -target x86_64-apple-macos11.0 \
     -o "$HERE/.bin-x86" "$HERE/main.swift" 2>/dev/null; then
  lipo -create "$HERE/.bin-arm64" "$HERE/.bin-x86" -output "$OUT/Contents/MacOS/$NAME"
  rm -f "$HERE/.bin-x86"
else
  echo "    (跳過 Intel 版本，僅建立 Apple Silicon 版)"
  cp "$HERE/.bin-arm64" "$OUT/Contents/MacOS/$NAME"
fi
rm -f "$HERE/.bin-arm64"
chmod +x "$OUT/Contents/MacOS/$NAME"

echo "==> 複製編輯器"
cp "$HTML" "$OUT/Contents/Resources/index.html"

cp "$HERE/Info.plist" "$OUT/Contents/Info.plist"

echo "==> 簽章 (ad-hoc)"
codesign --force --deep --sign - "$OUT" 2>/dev/null || echo "    (簽章略過)"

echo "==> 完成: $OUT"
du -sh "$OUT" | awk '{print "    大小: " $1}'
