#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/tests
xcrun swiftc Tests/make-pdf.swift -o build/tests/make-pdf -framework Cocoa
build/tests/make-pdf build/tests/selection-test.pdf

# Bundle the rules with each runner so tests also work on a clean Mac without Codex.
for SUITE in CoreTests ReaderTests PaperIndexTests; do
  TEST_APP="$PROJECT_DIR/build/tests/$SUITE.app"
  mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources"
  cp Resources/*.txt "$TEST_APP/Contents/Resources/"
  cat > "$TEST_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.YuyanWu-wyy.AcademicAssistant.$SUITE</string>
<key>CFBundleExecutable</key><string>$SUITE</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
  if [[ "$SUITE" == CoreTests ]]; then
    xcrun swiftc -swift-version 5 Sources/Core.swift Tests/CoreTests.swift -o "$TEST_APP/Contents/MacOS/$SUITE"
  else
    xcrun swiftc -swift-version 5 Sources/Core.swift Sources/PaperCore.swift Sources/ReadingHTML.swift Sources/PaperIndex.swift "Tests/$SUITE.swift" -framework Cocoa -framework PDFKit -o "$TEST_APP/Contents/MacOS/$SUITE"
  fi
  "$TEST_APP/Contents/MacOS/$SUITE"
done
