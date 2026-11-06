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
}
