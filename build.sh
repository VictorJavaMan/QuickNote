#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
APP="QuickNote.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BUILD_DIR="$PWD/.build"
mkdir -p "$BUILD_DIR/ModuleCache"
xcrun swiftc -module-cache-path "$BUILD_DIR/ModuleCache" Source/main.swift Source/Note.swift Source/PDFExporter.swift -o "$APP/Contents/MacOS/QuickNote" -framework AppKit -target arm64-apple-macosx13.0 -O
xcrun swift -module-cache-path "$BUILD_DIR/ModuleCache" Source/make-icon.swift "$BUILD_DIR/QuickNote.iconset"
python3 Source/package-icon.py "$BUILD_DIR/QuickNote.iconset" Assets/QuickNote.icns
cp Assets/QuickNote.icns "$APP/Contents/Resources/QuickNote.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QuickNote</string>
<key>CFBundleIdentifier</key><string>local.quicknote.floating</string>
<key>CFBundleName</key><string>QuickNote</string>
<key>CFBundleDisplayName</key><string>QuickNote</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.6</string>
<key>CFBundleVersion</key><string>8</string>
<key>CFBundleIconFile</key><string>QuickNote</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
