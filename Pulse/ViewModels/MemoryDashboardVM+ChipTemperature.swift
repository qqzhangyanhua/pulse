import Foundation

extension MemoryDashboardVM {
    // Chip-temperature page transitions live on `DashboardCore`. The reader stays on the sampler tick.

    /// Alert frames use this. Another page, a failed visit, or a non-finite value is nil, not 0.
    var machinePageCelsius: Double? {
        guard selectedPage == .machine else { return nil }
        guard chipTemperature.visitSucceeded, let celsius = chipTemperature.celsius, celsius.isFinite else { return nil }
        return celsius
    }
}
