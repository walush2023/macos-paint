#!/bin/bash
# 正式發行：Universal (arm64 + x86_64) release 編譯 → Developer ID 簽章(hardened runtime)
# → Apple 公證 → staple → 產出 Paint-macOS.dmg
#
# 用法：./release.sh
# 環境變數（可覆寫）：
#   SIGN_ID          簽章身分（預設：鑰匙圈中第一個 "Developer ID Application"）
#   NOTARY_PROFILE   notarytool 鑰匙圈設定檔名稱（xcrun notarytool store-credentials 建立）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

NOTARY_PROFILE="${NOTARY_PROFILE:-wintaskbar-notary}"
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"
[ -n "$SIGN_ID" ] || { echo "✗ 找不到 Developer ID Application 憑證" >&2; exit 1; }

# x86_64 需要 Xcode 的工具鏈（Command Line Tools 缺 x86_64 Swift 函式庫）
if [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "→ 編譯 Universal release..."
swift build -c release --arch arm64 --arch x86_64 --scratch-path .build/rel-uni 2>&1 | grep -E "error:|Build complete"
BIN="$ROOT/.build/rel-uni/out/Products/Release/Paint"
[ -f "$BIN" ] || { echo "✗ 編譯失敗" >&2; exit 1; }
lipo -info "$BIN"

echo "→ 單元測試..."
"$BIN" --unit-test | tail -1

# 圖示（沿用 build_app.sh 的產生邏輯）
[ -f "$ROOT/AppIcon.icns" ] || ./build_app.sh >/dev/null

APP="$ROOT/dist/Paint.app"
rm -rf "$ROOT/dist"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Paint"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "→ 簽章：$SIGN_ID"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "→ 送交公證（profile: $NOTARY_PROFILE）..."
ZIP="$ROOT/dist/Paint-macOS.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "→ Staple..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# DMG：App + 指向 /Applications 的捷徑，拖曳即可安裝
echo "→ 製作 DMG..."
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Info.plist")
DMG="$ROOT/dist/Paint-macOS.dmg"
STAGE="$ROOT/dist/dmg"
rm -rf "$STAGE" "$DMG" "$ZIP"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Paint $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

echo "→ 簽章並公證 DMG..."
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "✓ 完成：$DMG"
