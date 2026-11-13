import Foundation

/// Link state after a path update. Not a byte rate.
enum ConnectionStatus: Equatable, Sendable {
    case connected
    case disconnected
    case requiresConnection
}

/// The one primary interface. `.none` is only for an unsatisfied path.
enum ConnectionInterface: Equatable, Sendable {
    case wifi
    case ethernet
    case other
    case none
}

/// Path status the Darwin adapter can name without handing over `NWPath`.
enum HostPathStatus: Equatable, Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

/// Interface kind, in the path's preference order. The first entry is primary.
enum HostPathInterface: Equatable, Sendable {
    case wifi
    case wiredEthernet
    case other
}

/// One host link. Missing until a path arrives; that is not this value.
struct HostConnection: Equatable, Sendable {
    var status: ConnectionStatus
    var interface: ConnectionInterface

    /// Unsatisfied drops every interface. Otherwise the first listed kind wins.
    /// An empty list is still a link, so the interface is `.other`, not `.none`.
    static func project(status: HostPathStatus, interfaces: [HostPathInterface]) -> HostConnection {
        switch status {
        case .unsatisfied:
            return HostConnection(status: .disconnected, interface: .none)
        case .satisfied:
            return HostConnection(status: .connected, interface: primary(interfaces))
        case .requiresConnection:
            return HostConnection(status: .requiresConnection, interface: primary(interfaces))
        }
    }

    private static func primary(_ interfaces: [HostPathInterface]) -> ConnectionInterface {
        switch interfaces.first {
        case .wifi:
            return .wifi
        case .wiredEthernet:
            return .ethernet
        case .other, nil:
            return .other
        }
    }
}
