#!/bin/bash
set -e

FQBN="esp32:esp32:XIAO_ESP32S3"
CORE="esp32:esp32"
BOARD_URL="https://espressif.github.io/arduino-esp32/package_esp32_index.json"

echo "=== Streamer Setup ==="
echo ""

# 1. arduino-cli
if command -v arduino-cli &>/dev/null; then
    CLI_VER=$(arduino-cli version | awk '{print $2}')
    echo "[ok] arduino-cli v$CLI_VER"
    if command -v brew &>/dev/null && brew outdated arduino-cli 2>/dev/null | grep -q "arduino-cli"; then
        LATEST_CLI=$(brew info arduino-cli 2>/dev/null | head -1 | awk '{print $4}')
        echo "[!!] Newer arduino-cli available: v$LATEST_CLI (run: brew upgrade arduino-cli)"
    fi
else
    echo "[..] arduino-cli not found, installing via Homebrew..."
    if ! command -v brew &>/dev/null; then
        echo "[!!] Homebrew not found. Install it from https://brew.sh then re-run this script."
        exit 1
    fi
    brew install arduino-cli
    echo "[ok] arduino-cli installed"
fi

# 2. ESP32 board manager URL
if arduino-cli config dump 2>/dev/null | grep -q "espressif.github.io"; then
    echo "[ok] ESP32 board manager URL configured"
else
    echo "[..] Adding ESP32 board manager URL..."
    arduino-cli config add board_manager.additional_urls "$BOARD_URL"
    echo "[ok] Board manager URL added"
fi

# 3. esp32:esp32 core
arduino-cli core update-index 2>/dev/null
if arduino-cli core list 2>/dev/null | grep -q "^esp32:esp32"; then
    CORE_INSTALLED=$(arduino-cli core list 2>/dev/null | grep "^esp32:esp32" | awk '{print $2}')
    CORE_LATEST=$(arduino-cli core list 2>/dev/null | grep "^esp32:esp32" | awk '{print $3}')
    echo "[ok] $CORE core v$CORE_INSTALLED"
    if [ "$CORE_INSTALLED" != "$CORE_LATEST" ]; then
        echo "[!!] Newer core available: v$CORE_LATEST (run: arduino-cli core upgrade $CORE)"
    fi
else
    echo "[..] Installing $CORE core (this takes a minute)..."
    arduino-cli core install "$CORE"
    echo "[ok] $CORE core installed"
fi

# 4. WebSockets library
if arduino-cli lib list 2>/dev/null | grep -q "^WebSockets"; then
    LIB_VER=$(arduino-cli lib list 2>/dev/null | grep "^WebSockets" | awk '{print $2}')
    echo "[ok] WebSockets library v$LIB_VER"
else
    echo "[..] Installing WebSockets library..."
    arduino-cli lib install "WebSockets"
    echo "[ok] WebSockets library installed"
fi

# 5. Verify the board is known
if arduino-cli board listall 2>/dev/null | grep -q "XIAO_ESP32S3"; then
    echo "[ok] XIAO_ESP32S3 board available"
else
    echo "[!!] XIAO_ESP32S3 board not found — core may need updating"
    exit 1
fi

echo ""
echo "Setup complete. Run ./build.sh to compile."
