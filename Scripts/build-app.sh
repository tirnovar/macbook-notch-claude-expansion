#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/ClaudeNotchExpansion.app"
BINARY="$ROOT/.build/release/ClaudeNotchExpansion"
RESOURCES_SRC="$ROOT/Sources/ClaudeNotchExpansion/Resources"

echo "→ Building ClaudeNotchExpansion..."
cd "$ROOT"
swift build -c release 2>&1

echo "→ Assembling .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY"                                   "$APP/Contents/MacOS/ClaudeNotchExpansion"
cp "$RESOURCES_SRC/Info.plist"                 "$APP/Contents/Info.plist"
cp "$RESOURCES_SRC/claude-notch-hook.py"       "$APP/Contents/Resources/claude-notch-hook.py"
chmod 755 "$APP/Contents/Resources/claude-notch-hook.py"
[ -f "$RESOURCES_SRC/AppIcon.icns" ] && cp "$RESOURCES_SRC/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "✓ Built: $APP"
echo ""
echo "To run:    open \"$APP\""
echo "To install: cp -r \"$APP\" /Applications/"
