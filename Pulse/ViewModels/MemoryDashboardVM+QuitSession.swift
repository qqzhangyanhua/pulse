extension MemoryDashboardVM {
    var selectedPage: DashboardPage { navigation.selectedPage }
    var tableSort: ProcessTableSort { navigation.sort }
    var quitPhase: QuitPhase { sidebar.quitPhase }
    var quitMessage: String? { sidebar.quitMessage }

    /// Baseline for a quit estimate. A failed or missing frame never estimates.
    var quitReleaseBaseline: UInt64? {
        guard snapshot != nil, samplingFailed == false else { return nil }
        return snapshot?.usedBytes
    }

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
        guard selectedPage.allowsProcessQuit else { return }
        guard !selectedEnergyExitedOnly else { return }
        var store = quitOutcome
        let issued = ProcessQuitSession.ordinaryTerminate(
            store: &store,
            listSelectedPid: selectedPid,
            sidebarSubjectPid: sidebarSubjectPid,
            rows: rows,
            usedBytes: quitReleaseBaseline
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
        guard selectedPage.allowsProcessQuit else { return }
        guard !selectedEnergyExitedOnly else { return }
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
            rows: rows,
            usedBytes: quitReleaseBaseline
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

    /// Same-beat clear when the windowed keep hides `selectedPid`. OFF does not restore.
    func applyWindowedOnlySelection() {
        let next = WindowedAppFilter.selectedPid(
            current: selectedPid,
            page: selectedPage,
            windowedOnly: windowedOnlyFilter,
            windowedPids: { WindowedAppLookup.pids(in: rows) }
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

    /// ON selects the heaviest pid of the current name. OFF keeps the current pid.
    func applyGroupedByAppSelection() {
        let next = AppGroupProjection.selectedPid(
            current: selectedPid,
            rows: visibleRows,
            grouped: groupedByApp && AppGroupChrome.applies(on: selectedPage)
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
