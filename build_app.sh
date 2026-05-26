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

echo "→ 打包 .app..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Paint"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "✓ 完成: $APP"
