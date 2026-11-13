import CoreWLAN
import Foundation

/// One CoreWLAN read for the current sample. No timer and no network name.
enum HostWiFiReader {
    static func read() -> HostWiFiReading? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        return HostWiFi.reading(
            hasInterface: true,
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement()
        )
    }
}
