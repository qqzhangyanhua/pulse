import Foundation

extension DashboardCore {
    /// Memory Top card. A nil plan writes nothing, including the reveal generation.
    /// Filters that hide the row turn off before the pid is selected.
    mutating func locateMemoryTopApp(name: String, pid: Int32) -> [DashboardEffect] {
        guard let plan = TopAppLocation.plan(
            name: name,
            pid: pid,
            rows: rows,
            page: selectedPage,
            currentFilter: filter,
            currentRisingOnly: risingOnlyFilter,
            previousReveal: topAppLocateReveal
        ) else { return [] }
        var effects: [DashboardEffect] = []
        if case .replace(let nextName) = plan.nameFilter {
            effects += setFilter(nextName)
        }
        effects += setRisingOnly(false)
        effects += setWindowedOnly(false, windowedPids: windowedPids)
        if let accepted = ProcessSelection.acceptedPid(plan.acceptedPid, in: rows) {
            effects += select(pid: accepted)
        }
        topAppLocateReveal = plan.reveal
        return effects
    }

    /// Tree jump or return. A memory keep that would drop `pid` turns off first.
    mutating func focusProcessFromTree(_ pid: Int32) -> [DashboardEffect] {
        let next = ProcessTree.filtersAfterFocus(
            pid: pid,
            page: selectedPage,
            risingOnly: risingOnlyFilter,
            windowedOnly: windowedOnlyFilter,
            rows: rows,
            nameQuery: filter,
            seriesByPid: topMemorySeries,
            windowedPids: { windowedPids }
        )
        var effects: [DashboardEffect] = []
        effects += setRisingOnly(next.risingOnly)
        effects += setWindowedOnly(next.windowedOnly, windowedPids: windowedPids)
        if let accepted = ProcessSelection.acceptedPid(pid, in: rows) {
            effects += select(pid: accepted)
        }
        return effects
    }
}
