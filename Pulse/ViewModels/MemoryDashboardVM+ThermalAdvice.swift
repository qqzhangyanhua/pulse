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
}
