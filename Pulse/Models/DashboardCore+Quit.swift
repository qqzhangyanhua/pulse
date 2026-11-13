import Foundation

extension DashboardCore {
    /// Baseline for a quit estimate. A failed or missing frame never estimates.
    var quitReleaseBaseline: UInt64? {
        guard snapshot != nil, samplingFailed == false else { return nil }
        return snapshot?.usedBytes
    }

    var selectedEnergyExitedOnly: Bool {
        EnergyPage.blocksQuit(
            selectedPid: selectedPid,
            rememberedGeneration: selectedEnergyGeneration,
            liveRows: rows,
            liveGenerations: energyLiveGenerations,
            exited: exitedEnergyProcesses
        )
    }

    /// Keep an energy-page exit that `blocksQuit` still cares about.
    /// Applying the quit nil first would capture a nil generation before reconcile.
    func keepsExitedEnergySelection(replacingWith nextPid: Int32?) -> Bool {
        selectedPage == .energy && nextPid == nil && selectedEnergyExitedOnly
    }

    /// Ordinary quit. Empty when the page disallows it, the energy selection is exited-only, or no attempt is issued.
    /// A paused process asks to continue first, and does not start the quit attempt yet.
    mutating func quitSelected() -> [DashboardEffect] {
        guard selectedPage.allowsProcessQuit else { return [] }
        guard !selectedEnergyExitedOnly else { return [] }
        if let prompt = resumeBeforeQuitPrompt() {
            return [prompt]
        }
        var store = quitOutcome
        let issued = ProcessQuitSession.ordinaryTerminate(
            store: &store,
            listSelectedPid: selectedPid,
            sidebarSubjectPid: sidebarSubjectPid,
            rows: rows,
            usedBytes: quitReleaseBaseline
        )
        quitOutcome = store
        guard let issued else { return [] }
        return [.terminate(pid: issued.pid, force: false, token: issued.token)]
    }

    /// Opens the force confirmation. Empty when quit is not legal or a confirmation is already pending.
    mutating func beginForceQuit() -> [DashboardEffect] {
        guard selectedPage.allowsProcessQuit else { return [] }
        guard !selectedEnergyExitedOnly else { return [] }
        var store = quitOutcome
        let request = ProcessQuitSession.requestForce(
            store: &store,
            listSelectedPid: selectedPid,
            sidebarSubjectPid: sidebarSubjectPid,
            rows: rows
        )
        quitOutcome = store
        guard let request else { return [] }
        return [.confirmForceQuit(displayName: request.displayName, generation: request.generation)]
    }

    /// Cancel writes no terminate. Confirm publishes the issued attempt, then returns `terminate` with force.
    mutating func resolveForceQuit(generation: UInt64, confirmed: Bool) -> [DashboardEffect] {
        if !confirmed {
            var cancelled = quitOutcome
            ProcessQuitSession.cancelForce(store: &cancelled, generation: generation)
            quitOutcome = cancelled
            return []
        }
        var confirming = quitOutcome
        let issued = ProcessQuitSession.confirmForce(
            store: &confirming,
            generation: generation,
            listSelectedPid: selectedPid,
            rows: rows,
            usedBytes: quitReleaseBaseline
        )
        if issued == nil {
            ProcessQuitSession.releaseClosedForceConfirmation(
                store: &confirming,
                generation: generation,
                issued: issued
            )
        }
        quitOutcome = confirming
        guard let issued else { return [] }
        return [.terminate(pid: issued.pid, force: true, token: issued.token)]
    }

    /// Completion is the issued pid and token. A cancelled task leaves the store in the quitting phase.
    mutating func finishQuit(
        pid: Int32,
        token: UInt64,
        result: ProcessActionResult,
        taskCancelled: Bool
    ) {
        var finished = quitOutcome
        ProcessQuitSession.finish(
            store: &finished,
            pid: pid,
            token: token,
            result: result,
            taskCancelled: taskCancelled
        )
        quitOutcome = finished
    }

    /// Close the sidebar. The quit store stays unsettled.
    mutating func dismissSidebar() -> [DashboardEffect] {
        commitQuitSelection(ProcessQuitSession.dismissSidebar())
    }

    /// Terminates `pid`. A paused pid asks to continue first and does not terminate yet.
    /// The store changes only when this pid is the selected process-page pid and `ordinaryTerminate` issues one.
    mutating func beginThermalTerminate(pid: Int32) -> [DashboardEffect] {
        if let prompt = resumeBeforeQuitEffect(pid: pid) {
            return [prompt]
        }
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
        return [.terminate(pid: pid, force: false, token: issued?.token)]
    }

    /// List pid, then energy generation, then the sample's sidebar and detail.
    /// `select` still settles only the final list pid.
    mutating func absorbSampleSelection(_ effect: ProcessQuitSession.SampleEffect) -> [DashboardEffect] {
        var effects: [DashboardEffect] = []
        if selectedPid != effect.listSelectedPid, !keepsExitedEnergySelection(replacingWith: effect.listSelectedPid) {
            effects += select(pid: effect.listSelectedPid)
        }
        effects += reconcileEnergySelection()
        if sidebarSubjectPid != effect.sidebarSubjectPid {
            sidebarSubjectPid = effect.sidebarSubjectPid
        }
        if detail != effect.liveDetail {
            detail = effect.liveDetail
        }
        return effects
    }

    mutating func reconcileEnergySelection() -> [DashboardEffect] {
        let decision = EnergyPage.resolvedSelection(
            onEnergyPage: selectedPage == .energy,
            selectedPid: selectedPid,
            rememberedGeneration: selectedEnergyGeneration,
            liveRows: rows,
            liveGenerations: energyLiveGenerations
        )
        var effects: [DashboardEffect] = []
        if selectedPid != decision.pid {
            effects += select(pid: decision.pid)
        }
        selectedEnergyGeneration = decision.generation
        return effects
    }
}
