import Foundation

extension MemoryDashboardVM {
    /// Hour rates while the span is 1 小时. Otherwise the 1-minute window.
    var activeEnergyRates: [Int32: ProcessEnergyRates] { core.activeEnergyRates }
}
