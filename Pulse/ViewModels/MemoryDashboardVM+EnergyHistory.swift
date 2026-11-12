import Foundation

extension MemoryDashboardVM {
    func recordedEnergyHistory(rows: [ProcessRow], at date: Date) -> EnergyMachineHistory {
        var history = energyMachineHistory
        history.record(
            processWatts: processWatts(rows),
            batteryPercent: historyBatteryPercent,
            at: date
        )
        return history
    }

    private func processWatts(_ rows: [ProcessRow]) -> Double? {
        let known = rows.compactMap(\.energyWatts)
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    /// The 30-second energy-page read. Off this page, or with no percent, stays nil.
    private var historyBatteryPercent: Double? {
        guard selectedPage == .energy else { return nil }
        guard let reading = energyBatteryReading,
              reading.hasInternalBattery,
              let percent = reading.percent
        else { return nil }
        return Double(percent)
    }
}
