#!/bin/bash
set -e

FQBN="esp32:esp32:XIAO_ESP32S3:PSRAM=opi"
SKETCH="src/streamer"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Building for XIAO ESP32S3 ==="
echo ""
echo $SCRIPT_DIR

if ! command -v arduino-cli &>/dev/null; then
    echo "arduino-cli not found. Run ./setup.sh first."
    exit 1
fi

arduino-cli compile --fqbn "$FQBN" "$SCRIPT_DIR/$SKETCH"

echo ""
echo "Build succeeded. Run ./flash.sh to upload."
