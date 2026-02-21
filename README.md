# Streamer

ESP32S3 camera that streams video to an iOS companion app, which forwards frames to a vision API for real-time object detection.

## Architecture

```
ESP32S3 (SoftAP, 192.168.4.1)
  │
  ├── WiFi AP: "ESP32S3-Cam" / "streamer1"
  ├── WebSocket server on port 81 (binary JPEG frames @ 10fps)
  └── BLE advertising for device discovery
  │
  ▼
iPhone App (connects to ESP32 WiFi)
  │
  ├── Displays live camera preview
  ├── Forwards every 5th frame (~2fps) over cellular to vision API
  └── Overlays detection bounding boxes on preview
  │
  ▼
api.kortexa.ai/vision/ws (object detection)
  │
  └── Returns: class labels, confidence scores, bounding boxes
```

The phone joins the ESP32's WiFi for local frame transfer, while iOS automatically routes internet traffic (vision API) over cellular. No external WiFi infrastructure needed — works on the go.

## Hardware

- **Board**: Seeed XIAO ESP32S3 Sense (with camera module)
- **Button**: Push button on GPIO0 (start/stop toggle)
- **Power**: 3.7V LiPo battery

## Project Structure

```
streamer/
├── src/
│   └── streamer.ino          # ESP32 firmware
├── app/                       # iOS companion app (SwiftUI)
│   ├── project.yml            # XcodeGen spec
│   ├── generate.sh            # Creates .xcodeproj
│   └── Streamer/
│       ├── StreamerApp.swift
│       ├── ContentView.swift  # Preview + detection overlay + controls
│       ├── BLEManager.swift   # CoreBluetooth device discovery
│       ├── WiFiManager.swift  # NEHotspotConfiguration auto-join
│       ├── CameraStream.swift # WebSocket client to ESP32
│       └── VisionService.swift # Vision API client (cellular)
├── setup.sh                   # Install build toolchain
├── build.sh                   # Compile firmware
└── flash.sh                   # Flash to board
```

## ESP32 Setup

### Prerequisites

```bash
./setup.sh
```

This checks for (and installs if missing):
- `arduino-cli` (via Homebrew)
- `esp32:esp32` board core (via arduino-cli)
- `WebSockets` library (via arduino-cli)

Also warns if newer versions are available.

### Build

```bash
./build.sh
```

### Flash

Plug in the XIAO ESP32S3 via USB-C, then:

```bash
./flash.sh
```

Detects connected boards, lets you pick a port if multiple are found, flashes, and optionally opens the serial monitor at 115200 baud.

If the board isn't detected, hold the **BOOT** button while plugging in USB to enter download mode.

## iOS App Setup

### Generate Xcode Project

```bash
cd app
./generate.sh      # installs xcodegen via brew if needed
open Streamer.xcodeproj
```

### Build & Run

Build and run on a **real device** — BLE and NEHotspotConfiguration don't work in the simulator.

The app requires:
- iOS 17+
- Bluetooth permission (device discovery)
- Hotspot Configuration entitlement (auto-join ESP32 WiFi)

## Usage

1. Power on the ESP32
2. Open the Streamer app on your iPhone
3. The app automatically:
   - Discovers the ESP32 via BLE
   - Joins the ESP32's WiFi network
   - Connects to the camera WebSocket
4. Tap **Start** to begin streaming
5. Frames appear as a live preview with detection bounding boxes overlaid

The hardware button on GPIO0 also toggles streaming on/off.

## ESP32 WebSocket Protocol

The ESP32 runs a WebSocket server on `ws://192.168.4.1:81`.

**Incoming (text):** `"start"` / `"stop"` — control streaming

**Outgoing (binary):** Raw JPEG frame data

## Vision API Protocol

The app connects to `wss://api.kortexa.ai/vision/ws` over cellular.

**Outgoing (text/JSON):**
```json
{
  "type": "frame",
  "data": "data:image/jpeg;base64,<base64>",
  "confidence": 0.25,
  "frame_id": "frame_N",
  "timestamp": 1708000000000
}
```

**Incoming (text/JSON):**
```json
{
  "type": "detection",
  "data": {
    "detections": [
      {
        "class": "person",
        "confidence": 0.85,
        "bbox": [x1, y1, x2, y2]
      }
    ]
  }
}
```
