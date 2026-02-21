import SwiftUI

struct ContentView: View {
    @StateObject private var wifi = WiFiManager()
    @StateObject private var camera = CameraStream()
    @StateObject private var ai = AIService()

    @State private var isStreaming = false
    @State private var showAI = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.latestFrame != nil || ai.latestResult != nil {
                GeometryReader { geo in
                    // Show AI result or camera feed
                    if showAI, let aiImage = ai.latestResult {
                        Image(uiImage: aiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let camImage = camera.latestFrame {
                        Image(uiImage: camImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // Camera PiP (small preview in corner when showing AI)
                    if showAI, ai.latestResult != nil, let camImage = camera.latestFrame {
                        VStack {
                            Spacer()
                            HStack {
                                Image(uiImage: camImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 120)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                                    .padding(12)
                                Spacer()
                            }
                        }
                        .padding(.bottom, 100)
                    }
                }
            } else {
                // Placeholder with connect button
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)

                    if camera.isConnected {
                        Text("Camera connected — tap Start")
                            .foregroundColor(.gray)
                    } else {
                        Text("Connect to the camera WiFi")
                            .foregroundColor(.gray)

                        Button {
                            wifi.joinESP32Network()
                        } label: {
                            HStack {
                                Image(systemName: "wifi")
                                Text("Join ESP32S3-Cam")
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(20)
                        }

                        Text("Password: streamer1")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
            }

            // Controls
            VStack {
                // Status bar
                HStack(spacing: 16) {
                    StatusDot(label: "Cam", on: camera.isConnected)
                    StatusDot(label: "AI", on: ai.isConnected)
                    if ai.isProcessing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.white)
                    }
                    if !ai.debugStatus.isEmpty {
                        Text(ai.debugStatus)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding(.top, 8)

                Spacer()

                // Bottom controls
                HStack(spacing: 16) {
                    // Toggle camera/AI view
                    if ai.latestResult != nil {
                        Button {
                            showAI.toggle()
                        } label: {
                            Image(systemName: showAI ? "camera.fill" : "wand.and.stars")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial)
                                .cornerRadius(24)
                        }
                    }

                    // Start/Stop
                    Button {
                        toggleStream()
                    } label: {
                        HStack {
                            Image(systemName: isStreaming ? "stop.fill" : "play.fill")
                            Text(isStreaming ? "Stop" : "Start")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 140, height: 48)
                        .background(isStreaming ? Color.red : Color.green)
                        .cornerRadius(24)
                    }
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
        .onAppear {
            camera.onFrameData = { data in
                ai.processFrame(jpegData: data)
            }
            camera.connect()
        }
    }

    private func toggleStream() {
        isStreaming.toggle()
        if isStreaming {
            camera.sendCommand("start")
            ai.connect()
        } else {
            camera.sendCommand("stop")
            ai.disconnect()
        }
    }
}

struct StatusDot: View {
    let label: String
    let on: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(on ? Color.green : Color.red.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white)
        }
    }
}
