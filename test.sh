#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR="$PWD/.build/tests"
mkdir -p "$TEST_DIR"
xcrun swiftc -module-cache-path "$TEST_DIR/ModuleCache" -target arm64-apple-macosx13.0 Source/Note.swift Source/TextFileImporter.swift Source/PDFExporter.swift Tests/NoteTests.swift -framework AppKit -framework PDFKit -o "$TEST_DIR/NoteTests"
"$TEST_DIR/NoteTests" "$TEST_DIR"
