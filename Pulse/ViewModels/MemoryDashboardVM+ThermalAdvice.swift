import Foundation

extension MemoryDashboardVM {
    /// Top 3 while `thermalNotice` is showing. A nil notice drops the card without waiting out the throttle. An unmeasured projection does not publish and does not move the throttle.
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
        let projected = ThermalAdviceProjection.project(
            candidates,
            excludingPid: ProcessInfo.processInfo.processIdentifier
        )
        if projected.processes.isEmpty, projected.noHighLoad == false {
            return
        }
        thermalAdvice = projected
        thermalAdviceLastUpdate = now
    }

    /// Every click terminates this pid, with no confirm dialog. A selected process-page pid finishes that session only when `ordinaryTerminate` issues one.
    func terminateThermalAdvice(pid: Int32) async {
        await runCore { $0.beginThermalTerminate(pid: pid) }
    }
}
