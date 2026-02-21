// ESP32S3 Video Streaming over WebSocket with BLE Configuration
// Features: BLE WiFi config, video streaming control via BLE and button

#include <Arduino.h>
#include <WiFi.h>
#include <WebSocketsClient.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>
#include "esp_camera.h"

// Pin definitions for XIAO ESP32S3 Sense camera
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

// Button pin
#define BUTTON_PIN 0

// BLE UUIDs
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define WIFI_SSID_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define WIFI_PASS_CHAR_UUID "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e"
#define STREAM_CTRL_CHAR_UUID "a7b3c5d9-8f6e-4a2b-9c1d-3e5f7a9b2c4d"
#define SERVER_URL_CHAR_UUID "d4e5f6a7-b8c9-4d1e-2f3a-4b5c6d7e8f9a"

// Global variables
WebSocketsClient webSocket;
Preferences preferences;
BLEServer* pServer = NULL;
BLECharacteristic* pWifiSsidCharacteristic = NULL;
BLECharacteristic* pWifiPassCharacteristic = NULL;
BLECharacteristic* pStreamCtrlCharacteristic = NULL;
BLECharacteristic* pServerUrlCharacteristic = NULL;

String wifiSSID = "";
String wifiPassword = "";
String serverUrl = "";
int serverPort = 8080;
String serverPath = "/video";

bool deviceConnected = false;
bool oldDeviceConnected = false;
bool wifiConfigured = false;
bool streamActive = false;
bool buttonPressed = false;
unsigned long lastButtonPress = 0;
const unsigned long debounceDelay = 200;

camera_fb_t* fb = NULL;

// BLE Server Callbacks
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("BLE Client Connected");
    };

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("BLE Client Disconnected");
    }
};

// WiFi SSID Characteristic Callback
class WifiSsidCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        String value = pCharacteristic->getValue().c_str();
        if (value.length() > 0) {
            wifiSSID = value;
            preferences.putString("wifi_ssid", wifiSSID);
            Serial.println("WiFi SSID set: " + wifiSSID);
        }
    }
};

// WiFi Password Characteristic Callback
class WifiPassCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        String value = pCharacteristic->getValue().c_str();
        if (value.length() > 0) {
            wifiPassword = value;
            preferences.putString("wifi_pass", wifiPassword);
            Serial.println("WiFi Password set");
            wifiConfigured = true;
        }
    }
};

// Stream Control Characteristic Callback
class StreamCtrlCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        String value = pCharacteristic->getValue().c_str();
        if (value.length() > 0) {
            if (value == "1" || value == "start") {
                streamActive = true;
                Serial.println("Stream started via BLE");
            } else if (value == "0" || value == "stop") {
                streamActive = false;
                Serial.println("Stream stopped via BLE");
            }
        }
    }
};

// Server URL Characteristic Callback
class ServerUrlCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        String value = pCharacteristic->getValue().c_str();
        if (value.length() > 0) {
            serverUrl = value;
            preferences.putString("server_url", serverUrl);
            Serial.println("Server URL set: " + serverUrl);
            parseServerUrl();
        }
    }
};

void parseServerUrl() {
    // Parse server URL to extract host, port, path
    // Format: ws://hostname:port/path or hostname:port/path
    String url = serverUrl;
    
    if (url.startsWith("ws://")) {
        url = url.substring(5);
    } else if (url.startsWith("wss://")) {
        url = url.substring(6);
    }
    
    int portIndex = url.indexOf(':');
    int pathIndex = url.indexOf('/');
    
    if (portIndex > 0 && pathIndex > portIndex) {
        String host = url.substring(0, portIndex);
        serverPort = url.substring(portIndex + 1, pathIndex).toInt();
        serverPath = url.substring(pathIndex);
    } else if (pathIndex > 0) {
        String host = url.substring(0, pathIndex);
        serverPort = 8080;
        serverPath = url.substring(pathIndex);
    }
}

void initBLE() {
    Serial.println("Initializing BLE...");
    
    BLEDevice::init("ESP32S3-Camera");
    
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());
    
    BLEService *pService = pServer->createService(SERVICE_UUID);
    
    // WiFi SSID Characteristic
    pWifiSsidCharacteristic = pService->createCharacteristic(
        WIFI_SSID_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
    );
    pWifiSsidCharacteristic->setCallbacks(new WifiSsidCallbacks());
    pWifiSsidCharacteristic->addDescriptor(new BLE2902());
    
    // WiFi Password Characteristic
    pWifiPassCharacteristic = pService->createCharacteristic(
        WIFI_PASS_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pWifiPassCharacteristic->setCallbacks(new WifiPassCallbacks());
    pWifiPassCharacteristic->addDescriptor(new BLE2902());
    
    // Stream Control Characteristic
    pStreamCtrlCharacteristic = pService->createCharacteristic(
        STREAM_CTRL_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
    );
    pStreamCtrlCharacteristic->setCallbacks(new StreamCtrlCallbacks());
    pStreamCtrlCharacteristic->addDescriptor(new BLE2902());
    
    // Server URL Characteristic
    pServerUrlCharacteristic = pService->createCharacteristic(
        SERVER_URL_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
    );
    pServerUrlCharacteristic->setCallbacks(new ServerUrlCallbacks());
    pServerUrlCharacteristic->addDescriptor(new BLE2902());
    
    pService->start();
    
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();
    
    Serial.println("BLE advertising started");
}

void initCamera() {
    Serial.println("Initializing camera...");
    
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
        Serial.printf("Camera init failed with error 0x%x\n", err);
        return;
    }
    
    sensor_t * s = esp_camera_sensor_get();
    if (s) {
        s->set_vflip(s, 1);
        s->set_hmirror(s, 1);
    }
    
    Serial.println("Camera initialized successfully");
}

void connectWiFi() {
    if (wifiSSID.length() == 0) {
        Serial.println("WiFi SSID not configured");
        return;
    }
    
    Serial.print("Connecting to WiFi: ");
    Serial.println(wifiSSID);
    
    WiFi.mode(WIFI_STA);
    WiFi.begin(wifiSSID.c_str(), wifiPassword.c_str());
    
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30) {
        delay(500);
        Serial.print(".");
        attempts++;
    }
    
    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("\nWiFi connected");
        Serial.print("IP address: ");
        Serial.println(WiFi.localIP());
    } else {
        Serial.println("\nWiFi connection failed");
    }
}

void webSocketEvent(WStype_t type, uint8_t * payload, size_t length) {
    switch(type) {
        case WStype_DISCONNECTED:
            Serial.println("WebSocket Disconnected");
            break;
        case WStype_CONNECTED:
            Serial.println("WebSocket Connected");
            break;
        case WStype_TEXT:
            Serial.printf("WebSocket message: %s\n", payload);
            break;
        case WStype_BIN:
            break;
        case WStype_ERROR:
            Serial.println("WebSocket Error");
            break;
    }
}

void connectWebSocket() {
    if (serverUrl.length() == 0) {
        Serial.println("Server URL not configured");
        return;
    }
    
    parseServerUrl();
    
    String host = serverUrl;
    if (host.startsWith("ws://")) {
        host = host.substring(5);
    } else if (host.startsWith("wss://")) {
        host = host.substring(6);
    }
    
    int portIndex = host.indexOf(':');
    if (portIndex > 0) {
        host = host.substring(0, portIndex);
    } else {
        int pathIndex = host.indexOf('/');
        if (pathIndex > 0) {
            host = host.substring(0, pathIndex);
        }
    }
    
    Serial.printf("Connecting to WebSocket: %s:%d%s\n", host.c_str(), serverPort, serverPath.c_str());
    webSocket.begin(host, serverPort, serverPath);
    webSocket.onEvent(webSocketEvent);
    webSocket.setReconnectInterval(5000);
}

void sendFrame() {
    if (!webSocket.isConnected()) {
        return;
    }
    
    fb = esp_camera_fb_get();
    if (!fb) {
        Serial.println("Camera capture failed");
        return;
    }
    
    if (fb->format != PIXFORMAT_JPEG) {
        Serial.println("Non-JPEG frame detected");
        esp_camera_fb_return(fb);
        return;
    }
    
    // Send frame via WebSocket
    webSocket.sendBIN(fb->buf, fb->len);
    
    esp_camera_fb_return(fb);
}

void handleButton() {
    int buttonState = digitalRead(BUTTON_PIN);
    unsigned long currentTime = millis();
    
    if (buttonState == LOW && !buttonPressed && (currentTime - lastButtonPress > debounceDelay)) {
        buttonPressed = true;
        lastButtonPress = currentTime;
        streamActive = !streamActive;
        
        if (streamActive) {
            Serial.println("Stream started via button");
        } else {
            Serial.println("Stream stopped via button");
        }
    } else if (buttonState == HIGH) {
        buttonPressed = false;
    }
}

void setup() {
    Serial.begin(115200);
    delay(1000);
    
    Serial.println("ESP32S3 Camera WebSocket Streamer");
    
    // Initialize preferences
    preferences.begin("camera-ws", false);
    
    // Load saved WiFi credentials
    wifiSSID = preferences.getString("wifi_ssid", "");
    wifiPassword = preferences.getString("wifi_pass", "");
    serverUrl = preferences.getString("server_url", "");
    
    if (wifiSSID.length() > 0 && wifiPassword.length() > 0) {
        wifiConfigured = true;
    }