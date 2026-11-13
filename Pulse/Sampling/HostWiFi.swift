import Foundation

/// One Wi-Fi sample. RSSI 0 and a missing interface are not a 0 dBm signal.
struct HostWiFiReading: Equatable, Sendable {
    var rssi: Int?
    var noise: Int?
    var ssid: String?
}

enum HostWiFi {
    /// No interface is a missing reading. RSSI 0 is a missing signal, not zero.
    /// Any other RSSI is kept, including negatives. The network name stays unset.
    static func reading(hasInterface: Bool, rssi: Int, noise: Int) -> HostWiFiReading? {
        guard hasInterface else { return nil }
        return HostWiFiReading(
            rssi: rssi == 0 ? nil : rssi,
            noise: noise,
            ssid: nil
        )
    }
}
