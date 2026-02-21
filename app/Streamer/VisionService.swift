import Foundation
import UIKit

class AIService: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var latestResult: UIImage?
    @Published var isProcessing = false
    @Published var debugStatus = ""

    private var frameCounter = 0
    // Process every 10th frame (~1fps when ESP32 sends at 10fps)
    private let sendEveryN = 10
    private var pendingRequest = false
    private var pendingSince: Date?
    private var shouldReconnect = false
    private var isReconnecting = false

    private let falKey = "93fdf36e-dd04-47a4-ae6f-0deb8ed707b5:d309d11bc162a3bd1b0866b2e7186055"
    private let tokenURL = "https://rest.alpha.fal.ai/tokens/"
    private let wsBase = "wss://fal.run/fal-ai/flux-2/klein/realtime"

    var prompt = "Turn this into \"Living oil painting, melting gold and sapphire\""

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var jwtToken: String?
    private var tokenExpiry: Date?

    func connect() {
        shouldReconnect = true
        isReconnecting = false
        fetchTokenAndConnect()
    }

    func disconnect() {
        shouldReconnect = false
        isReconnecting = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        jwtToken = nil
        tokenExpiry = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.latestResult = nil
            self.isProcessing = false
            self.debugStatus = ""
        }
        frameCounter = 0
        pendingRequest = false
        pendingSince = nil
    }

    /// Throttles and forwards JPEG frame data to fal.ai via realtime WebSocket
    func processFrame(jpegData: Data) {
        frameCounter += 1
        guard frameCounter % sendEveryN == 0, isConnected else { return }

        // Reset stuck pending requests after 10 seconds
        if pendingRequest, let since = pendingSince, Date().timeIntervalSince(since) > 10 {
            DispatchQueue.main.async { self.debugStatus = "timeout, resending" }
            pendingRequest = false
        }
        guard !pendingRequest else { return }

        pendingRequest = true
        pendingSince = Date()
        DispatchQueue.main.async { self.isProcessing = true }

        // Crop to center square 480x480 and re-encode at low quality
        guard let base64 = cropAndCompress(jpegData: jpegData) else {
            pendingRequest = false
            DispatchQueue.main.async { self.isProcessing = false }
            return
        }

        let payload: [String: Any] = [
            "prompt": prompt,
            "image_url": "data:image/jpeg;base64,\(base64)",
            "image_size": "square",
            "num_inference_steps": 3,
            "seed": 35,
            "enable_interpolation": true
        ]

        let encoded = MsgPack.encode(payload)
        webSocket?.send(.data(encoded)) { [weak self] error in
            if let error {
                NSLog("[AI] send error: \(error.localizedDescription)")
                self?.pendingRequest = false
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    self?.debugStatus = "send error"
                }
            }
        }
    }

    // MARK: - Image Processing

    /// Crop to center square and re-encode at 50% JPEG quality
    private func cropAndCompress(jpegData: Data) -> String? {
        guard let image = UIImage(data: jpegData),
              let cgImage = image.cgImage else { return nil }

        let w = cgImage.width
        let h = cgImage.height
        let side = min(w, h)
        let x = (w - side) / 2
        let y = (h - side) / 2
        let cropRect = CGRect(x: x, y: y, width: side, height: side)

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        // Scale to 480x480
        let size = CGSize(width: 480, height: 480)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: size))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let compressed = scaled?.jpegData(compressionQuality: 0.5) else { return nil }
        return compressed.base64EncodedString()
    }

    // MARK: - Token & Connection

    private func fetchTokenAndConnect() {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Key \(falKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "allowed_apps": ["flux-2"],
            "token_expiration": 120
        ])

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self, let data,
                  let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) else {
                NSLog("[AI] token error: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { self?.debugStatus = "token error" }
                self?.isReconnecting = false
                return
            }
            self.jwtToken = token
            self.tokenExpiry = Date().addingTimeInterval(100) // refresh before 120s expiry
            self.connectWebSocket(token: token)
        }.resume()
    }

    private func connectWebSocket(token: String) {
        // Cancel old socket without triggering reconnect
        let oldSocket = webSocket
        webSocket = nil
        oldSocket?.cancel(with: .normalClosure, reason: nil)

        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let url = URL(string: "\(wsBase)?fal_jwt_token=\(token)")!
        webSocket = urlSession?.webSocketTask(with: URLRequest(url: url))
        webSocket?.resume()
    }

    // MARK: - Receive

    private func receiveMessage() {
        // Capture current socket to detect stale callbacks
        let currentSocket = webSocket
        currentSocket?.receive { [weak self] result in
            guard let self, self.webSocket === currentSocket else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessage()
            case .failure(let error):
                NSLog("[AI] receive error: \(error.localizedDescription)")
                self.pendingRequest = false
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isProcessing = false
                    self.debugStatus = "recv error"
                }
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            // Error or status messages come as JSON text
            DispatchQueue.main.async { self.debugStatus = "msg: \(text.prefix(60))" }
            if text.contains("\"Unauthorized\"") || text.contains("\"Forbidden\"") {
                scheduleReconnect()
            }

        case .data(let data):
            // Msgpack-encoded response
            guard let decoded = MsgPack.decode(data) as? [String: Any] else {
                DispatchQueue.main.async { self.debugStatus = "decode error \(data.count)B" }
                pendingRequest = false
                DispatchQueue.main.async { self.isProcessing = false }
                return
            }

            // Check for error
            if let status = decoded["status"] as? String, status == "error" {
                let err = (decoded["error"] as? String) ?? "unknown"
                DispatchQueue.main.async { self.debugStatus = "error: \(err)" }
                pendingRequest = false
                DispatchQueue.main.async { self.isProcessing = false }
                return
            }

            // Extract images from response
            // With interpolation: [interpolated_frame, current_frame]
            if let images = decoded["images"] as? [Any] {
                let elapsed = pendingSince.map { String(format: "%.1fs", Date().timeIntervalSince($0)) } ?? "?"
                var totalKB = 0
                for imgObj in images {
                    if let imgDict = imgObj as? [String: Any],
                       let imageData = imgDict["content"] as? Data,
                       let image = UIImage(data: imageData) {
                        totalKB += imageData.count / 1024
                        DispatchQueue.main.async {
                            self.latestResult = image
                        }
                        // Brief delay between interpolated and current frame
                        if images.count > 1 {
                            Thread.sleep(forTimeInterval: 0.05)
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.debugStatus = "\(images.count)f \(totalKB)KB in \(elapsed)"
                }
            }

            pendingRequest = false
            pendingSince = nil
            DispatchQueue.main.async { self.isProcessing = false }

        @unknown default:
            break
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        // Only handle if this is our current socket
        guard webSocket === webSocketTask else { return }
        NSLog("[AI] WebSocket connected")
        isReconnecting = false
        DispatchQueue.main.async {
            self.isConnected = true
            self.debugStatus = "connected"
        }
        receiveMessage()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // Only handle if this is our current socket
        guard webSocket === webSocketTask else { return }
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        NSLog("[AI] WebSocket closed: \(closeCode.rawValue), reason: \(reasonStr)")
        pendingRequest = false
        DispatchQueue.main.async {
            self.isConnected = false
            self.isProcessing = false
            self.debugStatus = "closed: \(reasonStr)"
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldReconnect, !isReconnecting else { return }
        isReconnecting = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.shouldReconnect else {
                self?.isReconnecting = false
                return
            }
            DispatchQueue.main.async { self.debugStatus = "reconnecting..." }
            self.fetchTokenAndConnect()
        }
    }
}
