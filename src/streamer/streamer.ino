// ESP32S3 Camera Streamer
// SoftAP + WebSocket server for local video streaming

#include <Arduino.h>
#include <WiFi.h>
#include <WebSocketsServer.h>
#include "esp_camera.h"

// XIAO ESP32S3 Sense camera pins
#define PWDN_GPIO_NUM     -1
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM     10
#define SIOD_GPIO_NUM     40
#define SIOC_GPIO_NUM     39
#define Y9_GPIO_NUM       48
#define Y8_GPIO_NUM       11
#define Y7_GPIO_NUM       12
#define Y6_GPIO_NUM       14
#define Y5_GPIO_NUM       16
#define Y4_GPIO_NUM       18
#define Y3_GPIO_NUM       17
#define Y2_GPIO_NUM       15
#define VSYNC_GPIO_NUM    38
#define HREF_GPIO_NUM     47
#define PCLK_GPIO_NUM     13

#define BUTTON_PIN 0

// SoftAP config
#define AP_SSID "ESP32S3-Cam"
#define AP_PASS "streamer1"
#define WS_PORT 81

// Frame rate control
#define TARGET_FPS 10
#define FRAME_INTERVAL_MS (1000 / TARGET_FPS)

WebSocketsServer wsServer(WS_PORT);

bool streamActive = false;
int connectedClients = 0;
unsigned long lastFrameTime = 0;

// Button debounce
bool buttonPressed = false;
unsigned long lastButtonPress = 0;
const unsigned long debounceDelay = 200;

void initCamera() {
    camera_config_t config;
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer = LEDC_TIMER_0;
    config.pin_d0 = Y2_GPIO_NUM;
    config.pin_d1 = Y3_GPIO_NUM;
    config.pin_d2 = Y4_GPIO_NUM;
    config.pin_d3 = Y5_GPIO_NUM;
    config.pin_d4 = Y6_GPIO_NUM;
    config.pin_d5 = Y7_GPIO_NUM;
    config.pin_d6 = Y8_GPIO_NUM;
    config.pin_d7 = Y9_GPIO_NUM;
    config.pin_xclk = XCLK_GPIO_NUM;
    config.pin_pclk = PCLK_GPIO_NUM;
    config.pin_vsync = VSYNC_GPIO_NUM;
    config.pin_href = HREF_GPIO_NUM;
    config.pin_sccb_sda = SIOD_GPIO_NUM;
    config.pin_sccb_scl = SIOC_GPIO_NUM;
    config.pin_pwdn = PWDN_GPIO_NUM;
    config.pin_reset = RESET_GPIO_NUM;
    config.xclk_freq_hz = 20000000;
    config.pixel_format = PIXFORMAT_JPEG;
    config.frame_size = FRAMESIZE_VGA;
    config.jpeg_quality = 12;
    config.fb_count = 2;
    config.grab_mode = CAMERA_GRAB_LATEST;

    esp_err_t err = esp_camera_init(&config);
    if (err != ESP_OK) {
        Serial.printf("Camera init failed: 0x%x\n", err);
        return;
    }

    sensor_t *s = esp_camera_sensor_get();
    if (s) {
        s->set_vflip(s, 1);
        s->set_hmirror(s, 1);
    }

    Serial.println("Camera ready");
}

void webSocketEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
    switch (type) {
        case WStype_CONNECTED:
            connectedClients++;
            Serial.printf("WS client %u connected (%d total)\n", num, connectedClients);
            break;
        case WStype_DISCONNECTED:
            if (connectedClients > 0) connectedClients--;
            Serial.printf("WS client %u disconnected (%d total)\n", num, connectedClients);
            break;
        case WStype_TEXT: {
            String msg = String((char*)payload);
            if (msg == "start") {
                streamActive = true;
                Serial.println("Stream started via WS");
            } else if (msg == "stop") {
                streamActive = false;
                Serial.println("Stream stopped via WS");
            }
            break;
        }
        default:
            break;
    }
}

void sendFrame() {
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
        Serial.println("Capture failed");
        return;
    }

    wsServer.broadcastBIN(fb->buf, fb->len);
    esp_camera_fb_return(fb);
}

void handleButton() {
    int state = digitalRead(BUTTON_PIN);
    unsigned long now = millis();

    if (state == LOW && !buttonPressed && (now - lastButtonPress > debounceDelay)) {
        buttonPressed = true;
        lastButtonPress = now;
        streamActive = !streamActive;
        Serial.printf("Stream %s via button\n", streamActive ? "started" : "stopped");
    } else if (state == HIGH) {
        buttonPressed = false;
    }
}

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("ESP32S3-Cam Streamer");

    initCamera();

    // Start SoftAP
    WiFi.softAP(AP_SSID, AP_PASS);
    Serial.printf("AP: %s (IP: %s)\n", AP_SSID, WiFi.softAPIP().toString().c_str());

    // Start WebSocket server
    wsServer.begin();
    wsServer.onEvent(webSocketEvent);
    Serial.printf("WS server on port %d\n", WS_PORT);

    pinMode(BUTTON_PIN, INPUT_PULLUP);

    Serial.println("Ready");
}

void loop() {
    wsServer.loop();
    handleButton();

    unsigned long now = millis();
    if (streamActive && connectedClients > 0 && (now - lastFrameTime >= FRAME_INTERVAL_MS)) {
        lastFrameTime = now;
        sendFrame();
    }
}
