import Foundation

extension MemoryDashboardVM {
    /// Hour rates while the span is 1 小时. Otherwise the 1-minute window.
    var activeEnergyRates: [Int32: ProcessEnergyRates] {
        switch energyRankingSpan {
        case .oneHour:
            return energyHourRates
        case .oneMinute:
            return energyWindowRates
        }
    }

    /// Keep the energy-page selection when that pid has just become an exited hour entry.
    func keepsExitedEnergySelection(replacingWith nextPid: Int32?) -> Bool {
        selectedPage == .energy && nextPid == nil && selectedEnergyExitedOnly
    }
}
