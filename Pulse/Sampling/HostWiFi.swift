import Foundation

/// Location permission for the Wi-Fi name. The system prompt is not this type's job.
enum WiFiSSIDPermission: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// One Wi-Fi sample. RSSI 0 and a missing interface are not a 0 dBm signal.
struct HostWiFiReading: Equatable, Sendable {
    var rssi: Int?
    var noise: Int?
    var ssid: String?
}

enum HostWiFi {
    /// No interface is a missing reading. RSSI 0 is a missing signal, not zero.
    /// Any other RSSI is kept, including negatives. `ssid` is stored only when passed.
    static func reading(hasInterface: Bool, rssi: Int, noise: Int, ssid: String? = nil) -> HostWiFiReading? {
        guard hasInterface else { return nil }
        return HostWiFiReading(
            rssi: rssi == 0 ? nil : rssi,
            noise: noise,
            ssid: ssid
        )
    }
}
