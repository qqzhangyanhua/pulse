import Foundation

extension DashboardCore {
    var selectedPage: DashboardPage { navigation.selectedPage }
    var tableSort: ProcessTableSort { navigation.sort }

    /// Hour rates while the span is 1 小时. Otherwise the 1-minute window.
    var activeEnergyRates: [Int32: ProcessEnergyRates] {
        switch energyRankingSpan {
        case .oneHour:
            return energyHourRates
        case .oneMinute:
            return energyWindowRates
        }
    }

    var visibleRows: [ProcessRow] {
        let named = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: filter,
            page: selectedPage,
            risingOnly: risingOnlyFilter,
            seriesByPid: topMemorySeries
        )
        let pids = windowedPids
        return WindowedAppFilter.apply(
            rows: named,
            page: selectedPage,
            windowedOnly: windowedOnlyFilter,
            windowedPids: { pids }
        )
    }

    /// Visible rows in the current table sort. Not stored.
    var sortedRows: [ProcessRow] {
        if selectedPage == .energy {
            return EnergyPage.sorted(
                visibleRows,
                windowRates: activeEnergyRates,
                grouped: groupedByApp,
                sort: tableSort
            )
        }
        let projected = AppGroupProjection.apply(rows: visibleRows, grouped: groupedByApp && AppGroupChrome.applies(on: selectedPage))
        return tableSort.ordered(projected)
    }

    var selectedRow: ProcessRow? {
        guard let selectedPid else { return nil }
        return sortedRows.first { $0.pid == selectedPid } ?? rows.first { $0.pid == selectedPid }
    }

    /// Unfiltered `rows` ordered by the published memory-page sort.
    /// Does not read the name query, rising-only keep, or a resource-tab live `tableSort`.
    var menuBarPopover: MenuBarPopoverSnapshot {
        MenuBarPopoverSnapshot.project(
            pressure: snapshot?.pressure,
            usedBytes: snapshot?.usedBytes,
            samplingFailed: samplingFailed,
            rows: rows,
            processListFailed: processListFailed,
            sort: publication.sort,
            busiestCorePercent: busiestCorePercent
        )
    }

    var processListScrollTarget: Int32? {
        ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows)
    }

    /// List selection, including the early return on an unstable pid.
    /// Capture, `detail = nil`, and `forwardSelectedPid` run only for the settled pid.
    mutating func select(pid: Int32?) -> [DashboardEffect] {
        guard pid != selectedPid else { return [] }
        selectedPid = pid
        while true {
            let effect = ProcessQuitSession.followListSelection(
                listSelectedPid: selectedPid,
                sidebarSubjectPid: sidebarSubjectPid,
                rows: rows
            )
            if selectedPid != effect.listSelectedPid {
                selectedPid = effect.listSelectedPid
                continue
            }
            if sidebarSubjectPid != effect.sidebarSubjectPid {
                sidebarSubjectPid = effect.sidebarSubjectPid
            }
            captureEnergySelectionGeneration()
            detail = nil
            return [.forwardSelectedPid(selectedPid)]
        }
    }

    mutating func selectPage(_ page: DashboardPage) -> [DashboardEffect] {
        navigation.select(page)
        return finishPageChange()
    }

    mutating func focusMemoryPage() -> [DashboardEffect] {
        navigation.focusMemoryPage()
        return finishPageChange()
    }

    mutating func setTableSort(_ sort: ProcessTableSort) -> [DashboardEffect] {
        navigation.updateSort(sort)
        return publishMemoryPageSort()
    }

    mutating func setFilter(_ text: String) -> [DashboardEffect] {
        filter = text
        return []
    }

    mutating func setRisingOnly(_ on: Bool) -> [DashboardEffect] {
        guard on != risingOnlyFilter else { return [] }
        risingOnlyFilter = on
        return applyRisingOnlySelection()
    }

    /// `windowedPids` replaces the stored set only when the switch turns on.
    mutating func setWindowedOnly(_ on: Bool, windowedPids: Set<Int32>) -> [DashboardEffect] {
        guard on != windowedOnlyFilter else { return [] }
        if on {
            self.windowedPids = windowedPids
        }
        windowedOnlyFilter = on
        return applyWindowedOnlySelection()
    }

    mutating func setGroupedByApp(_ on: Bool) -> [DashboardEffect] {
        guard on != groupedByApp else { return [] }
        groupedByApp = on
        return applyGroupedByAppSelection()
    }

    mutating func setEnergyRankingSpan(_ span: EnergyRankingSpan) -> [DashboardEffect] {
        energyRankingSpan = span
        return []
    }

    /// Name, then rising, then windowed. Grouping stays. A pid this switch already cleared is not restored.
    mutating func clearMemoryPageFilters() -> [DashboardEffect] {
        filter = ""
        var effects: [DashboardEffect] = []
        if risingOnlyFilter {
            risingOnlyFilter = false
            effects += applyRisingOnlySelection()
        }
        if windowedOnlyFilter {
            windowedOnlyFilter = false
            effects += applyWindowedOnlySelection()
        }
        return effects
    }

    mutating func applyRisingOnlySelection() -> [DashboardEffect] {
        let next = MemoryGrowthRisingFilter.selectedPid(
            current: selectedPid,
            rows: rows,
            nameQuery: filter,
            page: selectedPage,
            risingOnly: risingOnlyFilter,
            seriesByPid: topMemorySeries
        )
        guard next != selectedPid else { return [] }
        return commitQuitSelection(
            ProcessQuitSession.risingOnlySelection(
                nextListPid: next,
                sidebarSubjectPid: sidebarSubjectPid,
                rows: rows,
                store: quitOutcome
            )
        )
    }

    mutating func applyWindowedOnlySelection() -> [DashboardEffect] {
        let pids = windowedPids
        let next = WindowedAppFilter.selectedPid(
            current: selectedPid,
            page: selectedPage,
            windowedOnly: windowedOnlyFilter,
            windowedPids: { pids }
        )
        guard next != selectedPid else { return [] }
        return commitQuitSelection(
            ProcessQuitSession.risingOnlySelection(
                nextListPid: next,
                sidebarSubjectPid: sidebarSubjectPid,
                rows: rows,
                store: quitOutcome
            )
        )
    }

    mutating func applyGroupedByAppSelection() -> [DashboardEffect] {
        let next = AppGroupProjection.selectedPid(
            current: selectedPid,
            rows: visibleRows,
            grouped: groupedByApp && AppGroupChrome.applies(on: selectedPage)
        )
        guard next != selectedPid else { return [] }
        return commitQuitSelection(
            ProcessQuitSession.risingOnlySelection(
                nextListPid: next,
                sidebarSubjectPid: sidebarSubjectPid,
                rows: rows,
                store: quitOutcome
            )
        )
    }

    private mutating func finishPageChange() -> [DashboardEffect] {
        var effects = publishMemoryPageSort()
        effects.append(.setGPUSampling(on: selectedPage == .gpu))
        effects += applyRisingOnlySelection()
        effects += applyWindowedOnlySelection()
        if selectedPage == .machine {
            effects.append(.startMachineWatch)
        } else {
            effects.append(.stopMachineWatch)
        }
        if selectedPage == .energy {
            effects.append(.startEnergyBatteryWatch)
        } else {
            effects.append(.stopEnergyBatteryWatch)
        }
        return effects
    }

    mutating func commitQuitSelection(_ effect: ProcessQuitSession.Selection) -> [DashboardEffect] {
        var effects: [DashboardEffect] = []
        if selectedPid != effect.listSelectedPid {
            effects += select(pid: effect.listSelectedPid)
        }
        if sidebarSubjectPid != effect.sidebarSubjectPid {
            sidebarSubjectPid = effect.sidebarSubjectPid
        }
        return effects
    }

    private mutating func captureEnergySelectionGeneration() {
        selectedEnergyGeneration = selectedPage == .energy
            ? selectedPid.flatMap { energyLiveGenerations[$0] }
            : nil
    }
}
