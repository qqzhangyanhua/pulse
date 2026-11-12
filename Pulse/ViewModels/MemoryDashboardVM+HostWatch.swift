import Foundation

extension MemoryDashboardVM {
    func beginThermalWatch() {
        applyThermalState(ProcessInfo.processInfo.thermalState)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyThermalState(ProcessInfo.processInfo.thermalState)
            }
        }
    }

    func endThermalWatch() {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
    }

    func applyThermalState(_ state: ProcessInfo.ThermalState) {
        thermalNotice = ThermalNotice.message(for: ThermalCondition(state))
        if thermalNotice == nil {
            thermalAdvice = nil
            thermalAdviceLastUpdate = nil
        }
    }

    /// Read on entry, then every 30 seconds while the machine page stays selected.
    func syncMachineWatch() {
        guard selectedPage == .machine else {
            machineRefreshTask?.cancel()
            machineRefreshTask = nil
            return
        }
        guard machineRefreshTask == nil else { return }
        refreshMachineFacts()
        machineRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
                guard let self else { return }
                self.refreshMachineFacts()
            }
        }
    }

    func refreshMachineFacts() {
        let next = HostMachineReader.read()
        if next != machineFacts {
            machineFacts = next
        }
    }
}

private extension ThermalCondition {
    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .unknown
        }
    }
}
