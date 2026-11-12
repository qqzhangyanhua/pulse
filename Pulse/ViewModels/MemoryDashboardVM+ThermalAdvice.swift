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
        let issued: ProcessQuitIssued?
        if pid == selectedPid, selectedPage.allowsProcessQuit {
            var store = quitOutcome
            issued = ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: selectedPid,
                sidebarSubjectPid: sidebarSubjectPid,
                rows: rows,
                usedBytes: quitReleaseBaseline
            )
            quitOutcome = store
        } else {
            issued = nil
        }
        let result = await ProcessActions.terminate(pid: pid)
        if let issued {
            var finished = quitOutcome
            ProcessQuitSession.finish(
                store: &finished,
                pid: issued.pid,
                token: issued.token,
                result: result,
                taskCancelled: Task.isCancelled
            )
            quitOutcome = finished
        }
    }
}
