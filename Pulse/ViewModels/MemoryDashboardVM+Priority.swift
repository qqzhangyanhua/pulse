import Foundation

extension MemoryDashboardVM {
    func isLoweredPriority(pid: Int32) -> Bool {
        core.isLoweredPriority(pid: pid)
    }

    func priorityMenuOffer() -> PriorityMenuOffer? {
        core.priorityMenuOffer(selfUid: ProcessPause.uid)
    }

    func performPriorityOffer(_ offer: PriorityMenuOffer) async {
        switch offer {
        case .lower:
            await runCore { $0.lowerSelectedPriority(selfUid: ProcessPause.uid) }
        case .restore:
            guard let pid = core.selectedPid else { return }
            await runCore { $0.restoreLoweredPriority(pid: pid) }
        }
    }

    func restoreLoweredPriority(pid: Int32) async {
        await runCore { $0.restoreLoweredPriority(pid: pid) }
    }

    func restoreLoweredPrioritiesForQuit() {
        mutateCore { $0.restoreLoweredPrioritiesForQuit() }
    }
}
