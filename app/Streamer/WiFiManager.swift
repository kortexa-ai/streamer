import Foundation
import NetworkExtension

class WiFiManager: ObservableObject {
    @Published var isConnected = false

    func joinESP32Network() {
        let config = NEHotspotConfiguration(ssid: "ESP32S3-Cam", passphrase: "streamer1", isWEP: false)
        config.joinOnce = false

        NEHotspotConfigurationManager.shared.apply(config) { error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    // Already connected counts as success
                    if error.domain == NEHotspotConfigurationErrorDomain,
                       error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                        self.isConnected = true
                    } else {
                        print("WiFi join failed: \(error.localizedDescription)")
                        self.isConnected = false
                    }
                } else {
                    self.isConnected = true
                }
            }
        }
    }
}
