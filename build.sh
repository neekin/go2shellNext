#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
EXT_DIR="$PROJECT_DIR/extensions"
APP_DIR="$PROJECT_DIR/swift/App"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Go2ShellNext"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:--}"

echo "=== Go2ShellNext Build Script (Swift) ==="

echo "[1/5] Compiling FinderSync Extension..."
mkdir -p "$EXT_DIR/FinderSyncExt.appex/Contents/MacOS"

swiftc \
    -target arm64-apple-macosx12.0 \
    -framework FinderSync \
    -framework AppKit \
    -framework Foundation \
    -Osize \
    -o "$EXT_DIR/FinderSyncExt.appex/Contents/MacOS/FinderSyncExt" \
    "$EXT_DIR/FinderSyncExt.swift"

cp "$EXT_DIR/Info.plist" "$EXT_DIR/FinderSyncExt.appex/Contents/Info.plist"

if [ "$SIGNING_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --entitlements "$EXT_DIR/Entitlements.plist" \
        "$EXT_DIR/FinderSyncExt.appex"
else
    codesign --force --sign - \
        --entitlements "$EXT_DIR/Entitlements.plist" \
        "$EXT_DIR/FinderSyncExt.appex"
fi

echo "[2/5] Compiling main application..."
mkdir -p "$BUILD_DIR"
swiftc \
    -target arm64-apple-macosx12.0 \
    -O \
    -o "$BUILD_DIR/$APP_NAME" \
    "$APP_DIR"/*.swift

echo "[3/5] Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/PlugIns"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$APP_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp -R "$EXT_DIR/FinderSyncExt.appex" "$APP_BUNDLE/Contents/PlugIns/"

echo "[4/5] Signing..."
codesign --force --sign "$SIGNING_IDENTITY" \
    --entitlements "$APP_DIR/Entitlements.plist" \
    "$APP_BUNDLE"

echo "[5/5] Verifying..."
codesign --verify --deep --strict "$APP_BUNDLE" 2>&1 && echo "Signature: VALID" || { echo "Signature: INVALID"; exit 1; }

echo ""
echo "=== Build Complete ==="
echo "App bundle: $APP_BUNDLE"
echo "App size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
