import Foundation

extension DashboardCore {
    /// A nil notice drops the advice card immediately, without waiting out the throttle.
    mutating func apply(thermalCondition: ThermalCondition) -> [DashboardEffect] {
        noteHistoryThermal(thermalCondition)
        thermalNotice = ThermalNotice.message(for: thermalCondition)
        if thermalNotice == nil {
            thermalAdvice = nil
            thermalAdviceLastUpdate = nil
        }
        return []
    }

    /// Top 3 while `thermalNotice` is showing. An unmeasured projection does not publish and does not move the throttle.
    mutating func refreshThermalAdvice(now: Double) {
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
        let projected = ThermalAdviceProjection.project(candidates, excludingPid: ownPid)
        if projected.processes.isEmpty, projected.noHighLoad == false {
            return
        }
        thermalAdvice = projected
        thermalAdviceLastUpdate = now
    }
}
