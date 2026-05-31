#!/bin/bash
# 編譯 Swift 專案並打包成 .app
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "→ 編譯..."
# SwiftPM 在此環境的 release 連結器有間歇性 build.db I/O 錯誤，
# debug 兩次跑通即可，先用 debug 模式 bundle 避免阻塞。
swift build 2>&1 | tail -3
if [ ! -f "$ROOT/.build/debug/Paint" ]; then
    swift build 2>&1 | tail -3
fi

APP="$ROOT/Paint.app"
BIN="$ROOT/.build/debug/Paint"

if [ ! -f "$BIN" ]; then
    echo "✗ 找不到編譯產物: $BIN" >&2
    exit 1
fi

# 由 icon.png 產生圓角(macOS squircle) AppIcon.icns（若尚未存在或來源較新）
if [ -f "$ROOT/icon.png" ] && { [ ! -f "$ROOT/AppIcon.icns" ] || [ "$ROOT/icon.png" -nt "$ROOT/AppIcon.icns" ]; }; then
    echo "→ 產生圓角 App 圖標..."
    # 先把方形來源做成 macOS 圓角圖（四角圓潤、含邊距）
    ROUNDED="$ROOT/.build/AppIcon-rounded.png"
    "$BIN" --make-icon "$ROOT/icon.png" "$ROUNDED" >/dev/null 2>&1
    SRC_ICON="$ROUNDED"
    [ -f "$SRC_ICON" ] || SRC_ICON="$ROOT/icon.png"   # 後備：直接用方形
    ICONSET="$ROOT/AppIcon.iconset"
    rm -rf "$ICONSET"; mkdir "$ICONSET"
    for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
                "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
                "512 512x512" "1024 512x512@2x"; do
        set -- $spec
        sips -z "$1" "$1" "$SRC_ICON" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o "$ROOT/AppIcon.icns"
fi

echo "→ 打包 .app..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Paint"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/AppIcon.icns" ] && cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "✓ 完成: $APP"
