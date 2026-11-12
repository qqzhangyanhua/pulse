import Foundation

extension MemoryDashboardVM {
    /// Read on entry, then every 30 seconds while the energy page stays selected.
    func syncEnergyBatteryWatch() {
        guard selectedPage == .energy else {
            energyBatteryRefreshTask?.cancel()
            energyBatteryRefreshTask = nil
            return
        }
        guard energyBatteryRefreshTask == nil else { return }
        refreshEnergyBattery()
        energyBatteryRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
                guard let self else { return }
                self.refreshEnergyBattery()
            }
        }
    }

    func refreshEnergyBattery() {
        let reading = EnergyBatteryReader.read()
        energyBatteryReading = reading
        let next = EnergyBattery.card(reading)
        if next != energyBatteryCard {
            energyBatteryCard = next
        }
    }
}
