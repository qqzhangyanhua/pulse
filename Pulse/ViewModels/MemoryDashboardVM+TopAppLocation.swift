extension MemoryDashboardVM {
    /// Memory Top card. A nil plan writes nothing.
    func locateMemoryTopApp(name: String, pid: Int32) {
        guard let plan = TopAppLocation.plan(
            name: name,
            pid: pid,
            rows: rows,
            page: selectedPage,
            currentFilter: filter,
            currentRisingOnly: risingOnlyFilter,
            previousReveal: topAppLocateReveal
        ) else { return }
        if case .replace(let nextName) = plan.nameFilter {
            filter = nextName
        }
        risingOnlyFilter = false
        windowedOnlyFilter = false
        selectPidIfPresent(plan.acceptedPid)
        topAppLocateReveal = plan.reveal
    }

    /// Tree jump or return. A memory keep that would drop `pid` turns off first.
    func focusProcessFromTree(_ pid: Int32) {
        let next = ProcessTree.filtersAfterFocus(
            pid: pid,
            page: selectedPage,
            risingOnly: risingOnlyFilter,
            windowedOnly: windowedOnlyFilter,
            rows: rows,
            nameQuery: filter,
            seriesByPid: topMemorySeries,
            windowedPids: { WindowedAppLookup.pids(in: rows) }
        )
        risingOnlyFilter = next.risingOnly
        windowedOnlyFilter = next.windowedOnly
        selectPidIfPresent(pid)
    }
}
