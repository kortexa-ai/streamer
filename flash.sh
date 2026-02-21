#!/bin/bash
set -e

FQBN="esp32:esp32:XIAO_ESP32S3:PSRAM=opi"
SKETCH="src/streamer"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Flash XIAO ESP32S3 ==="
echo ""

if ! command -v arduino-cli &>/dev/null; then
    echo "arduino-cli not found. Run ./setup.sh first."
    exit 1
fi

# Collect serial ports (skip Bluetooth and header line)
PORTS=()
while IFS= read -r line; do
    PORTS+=("$line")
done < <(arduino-cli board list 2>/dev/null | tail -n +2 | grep -v "serial://.*Bluetooth" | grep -v "^$")

if [ ${#PORTS[@]} -eq 0 ]; then
    echo "No serial ports detected."
    echo ""
    echo "Troubleshooting:"
    echo "  1. Plug in the XIAO ESP32S3 via USB-C"
    echo "  2. If it still doesn't show, hold BOOT while plugging in"
    echo "  3. Re-run this script"
    exit 1
fi

echo "Detected ports:"
echo ""
for i in "${!PORTS[@]}"; do
    echo "  $((i+1))) ${PORTS[$i]}"
done
echo ""

if [ ${#PORTS[@]} -eq 1 ]; then
    PORT=$(echo "${PORTS[0]}" | awk '{print $1}')
    echo "Only one port found, using: $PORT"
else
    read -rp "Select port [1-${#PORTS[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#PORTS[@]} ]; then
        echo "Invalid selection."
        exit 1
    fi
    PORT=$(echo "${PORTS[$((choice-1))]}" | awk '{print $1}')
fi

echo ""
echo "Uploading to $PORT..."
echo ""

arduino-cli upload --fqbn "$FQBN" --port "$PORT" "$SCRIPT_DIR/$SKETCH"

echo ""
echo "Flash complete."
echo ""
read -rp "Open serial monitor? [Y/n]: " monitor
if [[ ! "$monitor" =~ ^[nN] ]]; then
    echo "Opening monitor at 115200 baud (Ctrl+C to exit)..."
    arduino-cli monitor --port "$PORT" --config baudrate=115200
fi
