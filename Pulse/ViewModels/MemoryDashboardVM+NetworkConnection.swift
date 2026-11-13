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
        hostConnection = connection
    }

    func publishSampledWiFi(_ reading: HostWiFiReading?) {
        hostWiFi = reading
    }

    /// Does not prompt. The allow button is the only request.
    func startWiFiSSIDWatch() {
        HostWiFiLocation.start { [weak self] permission in
            self?.ssidPermission = permission
        }
    }

    func allowWiFiSSID() {
        HostWiFiLocation.request()
    }

    /// Click path only. A second click while loading does not start another request.
    func requestPublicIP() {
        guard publicIPRequest != .loading else { return }
        publicIPRequest = publicIPRequest.begin()
        let queriedAt = Date()
        let transport = PublicIPURLSessionTransport()
        Task { [weak self] in
            let result = await PublicIPLookup.lookup(using: transport)
            guard let self else { return }
            switch result {
            case .success(let address):
                self.publicIPRequest = PublicIPRequestState.loading.succeed(address: address, at: queriedAt)
            case .failure:
                self.publicIPRequest = PublicIPRequestState.loading.fail()
            }
        }
    }
}
