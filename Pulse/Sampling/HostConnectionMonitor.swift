import Foundation
import Network

/// Pushes the current path to the dashboard. Started with the dashboard and cancelled in deinit.
final class HostConnectionMonitor {
    private let monitor = NWPathMonitor()
    private let onUpdate: (HostConnection) -> Void

    init(onUpdate: @escaping (HostConnection) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() {
        monitor.pathUpdateHandler = { [onUpdate] path in
            let connection = HostConnection.project(
                status: Self.pathStatus(path.status),
                interfaces: path.availableInterfaces.map(Self.interfaceKind)
            )
            MainActor.assumeIsolated {
                onUpdate(connection)
            }
        }
        monitor.start(queue: .main)
    }

    func cancel() {
        monitor.cancel()
    }

    private static func pathStatus(_ status: NWPath.Status) -> HostPathStatus {
        switch status {
        case .satisfied:
            return .satisfied
        case .unsatisfied:
            return .unsatisfied
        case .requiresConnection:
            return .requiresConnection
        @unknown default:
            return .unsatisfied
        }
    }

    private static func interfaceKind(_ interface: NWInterface) -> HostPathInterface {
        switch interface.type {
        case .wifi:
            return .wifi
        case .wiredEthernet:
            return .wiredEthernet
        default:
            return .other
        }
    }
}
