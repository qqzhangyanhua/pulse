enum ThermalAdviceThrottle {
    static let interval: Double = 5

    static func shouldUpdate(now: Double, lastUpdate: Double?) -> Bool {
        guard let lastUpdate else { return true }
        return now - lastUpdate >= interval
    }
}
