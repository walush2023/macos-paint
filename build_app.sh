#!/bin/bash
# 編譯 Swift 專案並打包成 .app
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "→ 編譯..."
swift build -c release 2>&1 | tail -3

APP="$ROOT/Paint.app"
BIN="$ROOT/.build/release/Paint"

if [ ! -f "$BIN" ]; then
    echo "✗ 找不到編譯產物: $BIN" >&2
    exit 1
fi

echo "→ 打包 .app..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Paint"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "✓ 完成: $APP"
