import Foundation

extension DashboardCore {
    mutating func apply(hostConnection: HostConnection) -> [DashboardEffect] {
        self.hostConnection = hostConnection
        return []
    }

    /// Permission updates that arrive without a prompt. Does not request location.
    mutating func apply(ssidPermission: WiFiSSIDPermission) -> [DashboardEffect] {
        self.ssidPermission = ssidPermission
        return []
    }

    /// A second click while loading does not start another lookup.
    /// `now` is the click time, not the time the response arrives.
    mutating func requestPublicIP(now: Date) -> [DashboardEffect] {
        guard publicIPRequest != .loading else { return [] }
        publicIPRequest = publicIPRequest.begin()
        return [.lookupPublicIP(queriedAt: now)]
    }

    /// Success and failure are applied from `.loading`, not from the current value.
    /// A nil address is a failure and keeps no previous address.
    mutating func finishPublicIPLookup(address: String?, queriedAt: Date) -> [DashboardEffect] {
        if let address {
            publicIPRequest = PublicIPRequestState.loading.succeed(address: address, at: queriedAt)
        } else {
            publicIPRequest = PublicIPRequestState.loading.fail()
        }
        return []
    }

    /// The only path that asks for location permission.
    mutating func allowWiFiSSID() -> [DashboardEffect] {
        [.requestLocationAuthorization]
    }

    /// Replaces the network-page rates. An empty map clears them. Does not start `nettop`.
    mutating func apply(processNetworkRates rates: [Int32: ProcessNetworkRate]) -> [DashboardEffect] {
        processNetworkRates = rates
        return []
    }
}
