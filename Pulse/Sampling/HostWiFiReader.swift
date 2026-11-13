import CoreWLAN
import Foundation

/// One CoreWLAN read for the current sample. No timer.
/// The network name is read only when Location is already authorized.
enum HostWiFiReader {
    static func read() -> HostWiFiReading? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let permission = HostWiFiLocation.currentPermission()
        let name = permission == .authorized ? interface.ssid() : nil
        return HostWiFi.reading(
            hasInterface: true,
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement(),
            ssid: name
        )
    }
}
