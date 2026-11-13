import Foundation

extension MemoryDashboardVM {
    func beginConnectionWatch() {
        let monitor = HostConnectionMonitor { [weak self] connection in
            self?.publishHostConnection(connection)
        }
        hostConnectionMonitor = monitor
        monitor.start()
    }

    func endConnectionWatch() {
        hostConnectionMonitor?.cancel()
        hostConnectionMonitor = nil
    }
}
