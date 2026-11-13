import Foundation

struct NetworkConnectionRow: Equatable, Sendable {
    var title: String
    var value: String
}

/// Wi-Fi name row. The allow flag is the only prompt affordance.
struct NetworkConnectionSSID: Equatable, Sendable {
    var title: String
    var value: String
    var note: String?
    var allowsRequest: Bool
    var help: String?
}

/// Status, type, signal, and SSID. Nil is missing 「—」, not a disconnected link.
/// Signal and SSID exist only when the primary interface is Wi-Fi.
struct NetworkConnectionCard: Equatable, Sendable {
    var status: NetworkConnectionRow
    var type: NetworkConnectionRow
    var signal: NetworkConnectionRow?
    var ssid: NetworkConnectionSSID?

    static func project(
        _ connection: HostConnection?,
        wifi: HostWiFiReading? = nil,
        ssidPermission: WiFiSSIDPermission = .notDetermined
    ) -> NetworkConnectionCard {
        NetworkConnectionCard(
            status: NetworkConnectionRow(
                title: NetworkPageCopy.connectionStatusTitle,
                value: statusValue(connection?.status)
            ),
            type: NetworkConnectionRow(
                title: NetworkPageCopy.connectionTypeTitle,
                value: typeValue(connection?.interface)
            ),
            signal: signalRow(interface: connection?.interface, wifi: wifi),
            ssid: ssidRow(interface: connection?.interface, wifi: wifi, permission: ssidPermission)
        )
    }

    private static func ssidRow(
        interface: ConnectionInterface?,
        wifi: HostWiFiReading?,
        permission: WiFiSSIDPermission
    ) -> NetworkConnectionSSID? {
        guard interface == .wifi else { return nil }
        switch permission {
        case .notDetermined:
            return NetworkConnectionSSID(
                title: NetworkPageCopy.connectionSSIDTitle,
                value: NetworkRateText.missing,
                note: NetworkPageCopy.ssidNeedsLocation,
                allowsRequest: true,
                help: nil
            )
        case .denied:
            return NetworkConnectionSSID(
                title: NetworkPageCopy.connectionSSIDTitle,
                value: NetworkRateText.missing,
                note: NetworkPageCopy.ssidLocationDenied,
                allowsRequest: false,
                help: nil
            )
        case .authorized:
            return NetworkConnectionSSID(
                title: NetworkPageCopy.connectionSSIDTitle,
                value: wifi?.ssid ?? NetworkRateText.missing,
                note: nil,
                allowsRequest: false,
                help: wifi?.ssid
            )
        }
    }

    private static func signalRow(interface: ConnectionInterface?, wifi: HostWiFiReading?) -> NetworkConnectionRow? {
        guard interface == .wifi else { return nil }
        return NetworkConnectionRow(
            title: NetworkPageCopy.connectionSignalTitle,
            value: WiFiSignalText.value(rssi: wifi?.rssi)
        )
    }

    private static func statusValue(_ status: ConnectionStatus?) -> String {
        switch status {
        case .connected:
            return NetworkPageCopy.connectionConnected
        case .disconnected:
            return NetworkPageCopy.connectionDisconnected
        case .requiresConnection:
            return NetworkPageCopy.connectionRequiresLogin
        case nil:
            return NetworkRateText.missing
        }
    }

    private static func typeValue(_ interface: ConnectionInterface?) -> String {
        guard let interface else { return NetworkRateText.missing }
        switch interface {
        case .wifi:
            return NetworkPageCopy.connectionWiFi
        case .ethernet:
            return NetworkPageCopy.connectionEthernet
        case .other:
            return NetworkPageCopy.connectionOther
        case .none:
            return NetworkPageCopy.connectionDisconnected
        }
    }
}

/// Qualitative band plus dBm. The sign is U+2212, not a hyphen.
enum WiFiSignalText {
    static func value(rssi: Int?) -> String {
        guard let rssi else { return NetworkRateText.missing }
        return "\(band(rssi)) (\(decibels(rssi)) dBm)"
    }

    /// RSSI ≥ −60 is 强, −70…−61 is 中, ≤ −71 is 弱. −60 is 强, not 中.
    private static func band(_ rssi: Int) -> String {
        if rssi >= -60 { return NetworkPageCopy.signalStrong }
        if rssi >= -70 { return NetworkPageCopy.signalMedium }
        return NetworkPageCopy.signalWeak
    }

    private static func decibels(_ rssi: Int) -> String {
        if rssi < 0 {
            return "\u{2212}\(abs(rssi))"
        }
        return String(rssi)
    }
}
