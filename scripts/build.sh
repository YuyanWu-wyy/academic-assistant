#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/学术助手.app"
MINIMUM_MACOS=14.0

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Building Academic Assistant requires macOS.' >&2
  exit 1
fi
xcrun --find swiftc >/dev/null
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp -X "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp -X "$PROJECT_DIR/Resources/"*.txt "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
SOURCES=("$PROJECT_DIR/Sources/"*.swift)
FRAMEWORKS=(-framework Cocoa -framework Carbon -framework ApplicationServices -framework Security -framework PDFKit -framework WebKit)

# The default builds for this Mac. Use --universal to build both Mac architectures.
if [[ "${1:-}" == --universal ]]; then
  for ARCH in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos$MINIMUM_MACOS" "${SOURCES[@]}" "${FRAMEWORKS[@]}" -o "$PROJECT_DIR/build/AcademicAssistant-$ARCH"
  done
  xcrun lipo -create "$PROJECT_DIR/build/AcademicAssistant-arm64" "$PROJECT_DIR/build/AcademicAssistant-x86_64" -output "$APP_DIR/Contents/MacOS/AcademicAssistant"
elif [[ $# -eq 0 ]]; then
  xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos$MINIMUM_MACOS" "${SOURCES[@]}" "${FRAMEWORKS[@]}" -o "$APP_DIR/Contents/MacOS/AcademicAssistant"
else
  echo 'Usage: ./scripts/build.sh [--universal]' >&2
  exit 1
fi

# Ad-hoc signing supports local builds; this is not Developer ID notarization.
# Finder metadata in copied build resources is incompatible with code signing.
# Only remove these two metadata attributes from the generated bundle.
xattr -dr com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
echo "Built: $APP_DIR"
