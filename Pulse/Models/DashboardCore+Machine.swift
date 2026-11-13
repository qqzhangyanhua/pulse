import Foundation

extension DashboardCore {
    /// Stores the reading and publishes the card only when `card(_:)` changes.
    /// A reading with no internal battery hides the card.
    mutating func apply(energyBatteryReading reading: EnergyBatteryReading) -> [DashboardEffect] {
        energyBatteryReading = reading
        let next = EnergyBattery.card(reading)
        if next != energyBatteryCard {
            energyBatteryCard = next
        }
        return []
    }

    /// The 30-second energy-page read. Off this page, or with no percent, stays nil.
    func historyBatteryPercent(on page: DashboardPage) -> Double? {
        guard page == .energy else { return nil }
        guard let reading = energyBatteryReading,
              reading.hasInternalBattery,
              let percent = reading.percent
        else { return nil }
        return Double(percent)
    }

    /// Assigns only when the facts differ. Does not invent a value before the reader returns.
    mutating func apply(machineFacts next: MachineFacts) -> [DashboardEffect] {
        if next != machineFacts {
            machineFacts = next
        }
        return []
    }
}
