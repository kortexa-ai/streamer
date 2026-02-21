#!/bin/bash
set -e
cd "$(dirname "$0")"

if ! command -v xcodegen &>/dev/null; then
    echo "Installing xcodegen..."
    brew install xcodegen
fi

xcodegen generate
echo "Done. Open Streamer.xcodeproj in Xcode."
