#!/usr/bin/env bash
#
# bundle.sh — Build a release binary and assemble Intentime.app
#
# Usage:
#   ./scripts/bundle.sh           # Build release + bundle
#   ./scripts/bundle.sh --sign    # Build release + bundle + ad-hoc codesign
#
# Output: build/Intentime.app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Intentime"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

SIGN=false
if [[ "${1:-}" == "--sign" ]]; then
    SIGN=true
fi

echo "==> Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

# Locate the built binary
BINARY="$PROJECT_DIR/.build/release/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
    BINARY="$(find "$PROJECT_DIR/.build" -path "*/release/$APP_NAME" -type f | head -1)"
fi

if [[ ! -f "$BINARY" ]]; then
    echo "Error: Could not find release binary" >&2
    exit 1
fi

echo "==> Assembling $APP_NAME.app..."

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Create bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BINARY" "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy app resources (including AppIcon.icns)
if [[ -d "$PROJECT_DIR/Resources" ]]; then
    cp -R "$PROJECT_DIR/Resources/." "$RESOURCES_DIR/"
fi

# Write PkgInfo
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# Optional: codesign
if $SIGN; then
    echo "==> Code signing (ad-hoc)..."
    codesign --force --sign - "$APP_BUNDLE"
fi

echo "==> Done: $APP_BUNDLE"
du -sh "$APP_BUNDLE"
