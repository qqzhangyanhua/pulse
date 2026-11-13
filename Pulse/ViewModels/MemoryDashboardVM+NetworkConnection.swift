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

    func publishHostConnection(_ connection: HostConnection) {
        mutateCore { $0.apply(hostConnection: connection) }
    }

    /// Does not prompt. The allow button is the only request.
    func startWiFiSSIDWatch() {
        HostWiFiLocation.start { [weak self] permission in
            self?.mutateCore { $0.apply(ssidPermission: permission) }
        }
    }

    func allowWiFiSSID() {
        mutateCore { $0.allowWiFiSSID() }
    }

    /// Click path only. A second click while loading does not start another request.
    func requestPublicIP() {
        mutateCore { $0.requestPublicIP(now: Date()) }
    }
}
