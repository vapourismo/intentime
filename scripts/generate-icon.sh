#!/usr/bin/env bash
#
# generate-icon.sh — Generate the app icon files used by the macOS bundle.
#
# Usage:
#   ./scripts/generate-icon.sh
#
# Output:
#   assets/AppIcon-1024.png
#   Resources/AppIcon.icns

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="$PROJECT_DIR/assets"
RESOURCES_DIR="$PROJECT_DIR/Resources"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
SOURCE_PNG="$ASSETS_DIR/AppIcon-1024.png"
OUTPUT_ICNS="$RESOURCES_DIR/AppIcon.icns"

cleanup() {
    rm -rf "$(dirname "$ICONSET_DIR")"
}
trap cleanup EXIT

mkdir -p "$ASSETS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$ICONSET_DIR"

echo "==> Rendering template icon..."
swift "$SCRIPT_DIR/generate_icon.swift" "$SOURCE_PNG"

echo "==> Building AppIcon.iconset..."
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE_PNG" \
        --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$SOURCE_PNG" \
        --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

echo "==> Creating AppIcon.icns..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

echo "==> Done:"
echo "    $SOURCE_PNG"
echo "    $OUTPUT_ICNS"
