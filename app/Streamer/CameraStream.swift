import Foundation
import UIKit

class CameraStream: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var latestFrame: UIImage?

    /// Called with raw JPEG data for each received frame
    var onFrameData: ((Data) -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var shouldReconnect = false
    private let reconnectDelay: TimeInterval = 2.0

    func connect() {
        shouldReconnect = true
        attemptConnect()
    }

    func disconnect() {
        shouldReconnect = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.latestFrame = nil
        }
    }

    func sendCommand(_ command: String) {
        webSocket?.send(.string(command)) { error in
            if let error { print("WS send error: \(error)") }
        }
    }

    private func attemptConnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil

        let url = URL(string: "ws://192.168.4.1:81")!
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        DispatchQueue.main.async { self.isConnected = false }
        DispatchQueue.global().asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self, self.shouldReconnect else { return }
            self.attemptConnect()
        }
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .data(let data) = message, let image = UIImage(data: data) {
                    DispatchQueue.main.async { self?.latestFrame = image }
                    self?.onFrameData?(data)
                }
                self?.receiveMessage()
            case .failure(let error):
                print("WS receive error: \(error)")
                self?.scheduleReconnect()
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.isConnected = true }
        receiveMessage()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        scheduleReconnect()
    }
}
