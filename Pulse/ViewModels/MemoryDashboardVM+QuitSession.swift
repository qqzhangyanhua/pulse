extension MemoryDashboardVM {
    /// Close the sidebar. The quit store stays unsettled.
    func dismissSidebar() {
        let effect = ProcessQuitSession.dismissSidebar()
        if selectedPid != effect.listSelectedPid {
            selectedPid = effect.listSelectedPid
        }
        if sidebarSubjectPid != effect.sidebarSubjectPid {
            sidebarSubjectPid = effect.sidebarSubjectPid
        }
    }

    func quitSelected() async {
        var store = quitOutcome
        let issued = ProcessQuitSession.ordinaryTerminate(
            store: &store,
            listSelectedPid: selectedPid,
            sidebarSubjectPid: sidebarSubjectPid,
            rows: rows
        )
        quitOutcome = store
        guard let issued else { return }
        let result = await ProcessActions.terminate(pid: issued.pid)
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

    func forceQuitSelected() async {
        var store = quitOutcome
        let request = ProcessQuitSession.requestForce(
            store: &store,
            listSelectedPid: selectedPid,
            sidebarSubjectPid: sidebarSubjectPid,
            rows: rows
        )
        quitOutcome = store
        guard let request else { return }
        let confirmed = ProcessActions.confirmForceQuit(displayName: request.displayName)
        if !confirmed {
            var cancelled = quitOutcome
            ProcessQuitSession.cancelForce(store: &cancelled, generation: request.generation)
            quitOutcome = cancelled
            return
        }
        var confirming = quitOutcome
        let issued = ProcessQuitSession.confirmForce(
            store: &confirming,
            generation: request.generation,
            listSelectedPid: selectedPid,
            rows: rows
        )
        if issued == nil {
            ProcessQuitSession.releaseClosedForceConfirmation(
                store: &confirming,
                generation: request.generation,
                issued: issued
            )
        }
        quitOutcome = confirming
        guard let issued else { return }
        let result = await ProcessActions.forceTerminate(pid: issued.pid)
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

    /// Same-beat clear when the rising-only keep hides `selectedPid`. OFF does not restore.
    func applyRisingOnlySelection() {
        let next = MemoryGrowthRisingFilter.selectedPid(
            current: selectedPid,
            rows: rows,
            nameQuery: filter,
            page: selectedPage,
            risingOnly: risingOnlyFilter,
            seriesByPid: topMemorySeries
        )
        guard next != selectedPid else { return }
        let effect = ProcessQuitSession.risingOnlySelection(
            nextListPid: next,
            sidebarSubjectPid: sidebarSubjectPid,
            rows: rows,
            store: quitOutcome
        )
        if selectedPid != effect.listSelectedPid {
            selectedPid = effect.listSelectedPid
        }
        if sidebarSubjectPid != effect.sidebarSubjectPid {
            sidebarSubjectPid = effect.sidebarSubjectPid
        }
    }
}
