import Foundation

extension MemoryDashboardVM {
    /// Top 3 while `thermalNotice` is showing. A nil notice drops the card without waiting out the throttle.
    func refreshThermalAdvice(now: Double) {
        guard thermalNotice != nil else {
            thermalAdvice = nil
            thermalAdviceLastUpdate = nil
            return
        }
        guard ThermalAdviceThrottle.shouldUpdate(now: now, lastUpdate: thermalAdviceLastUpdate) else {
            return
        }
        let candidates = rows.map { row in
            ThermalAdviceCandidate(
                pid: row.pid,
                name: row.name,
                cpuPercent: row.cpuPercent,
                bundleIdentifier: row.bundleIdentifier,
                executablePath: row.executablePath
            )
        }
        thermalAdvice = ThermalAdviceProjection.project(
            candidates,
            excludingPid: ProcessInfo.processInfo.processIdentifier
        )
        thermalAdviceLastUpdate = now
    }

    /// Process-page selection goes through `quitSelected` so the sidebar stays in step. Any other pid, including one listed on the machine page, is terminated directly and leaves the selection alone.
    func terminateThermalAdvice(pid: Int32) async {
        if pid == selectedPid, selectedPage.allowsProcessQuit {
            await quitSelected()
            return
        }
        _ = await ProcessActions.terminate(pid: pid)
    }
}
