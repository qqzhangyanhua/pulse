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
        guard reading != energyBatteryReading else { return }
        mutateCore { $0.apply(energyBatteryReading: reading) }
    }
}
