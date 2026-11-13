import Foundation

extension MemoryDashboardVM {
    var pausedLedger: PausedProcessLedger { core.pausedLedger }

    func isPaused(pid: Int32) -> Bool {
        core.isPaused(pid: pid)
    }

    func pauseMenuOffer() -> PauseMenuOffer? {
        core.pauseMenuOffer(selfUid: ProcessPause.uid)
    }

    func installPausedLedger(_ ledger: PausedProcessLedger) {
        mutateCore { core in
            core.installPausedLedger(ledger)
            return []
        }
    }

    func performPauseOffer(_ offer: PauseMenuOffer) async {
        switch offer {
        case .pause:
            await runCore { $0.pauseSelected(selfUid: ProcessPause.uid) }
        case .resume:
            guard let pid = core.selectedPid else { return }
            await runCore { $0.resumePaused(pid: pid) }
        }
    }

    func resumePausedProcess(pid: Int32) async {
        await runCore { $0.resumePaused(pid: pid) }
    }
}
