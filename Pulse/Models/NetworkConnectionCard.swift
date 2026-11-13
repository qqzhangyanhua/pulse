import Foundation

struct NetworkConnectionRow: Equatable, Sendable {
    var title: String
    var value: String
}

/// Status and type only. Nil is missing 「—」, not a disconnected link.
struct NetworkConnectionCard: Equatable, Sendable {
    var status: NetworkConnectionRow
    var type: NetworkConnectionRow

    static func project(_ connection: HostConnection?) -> NetworkConnectionCard {
        NetworkConnectionCard(
            status: NetworkConnectionRow(
                title: NetworkPageCopy.connectionStatusTitle,
                value: statusValue(connection?.status)
            ),
            type: NetworkConnectionRow(
                title: NetworkPageCopy.connectionTypeTitle,
                value: typeValue(connection?.interface)
            )
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
