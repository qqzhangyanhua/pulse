extension MemoryDashboardVM {
    var selectedPage: DashboardPage { navigation.selectedPage }
    var tableSort: ProcessTableSort { navigation.sort }

    /// Per-row memory-tab list badge. Top5 ∩ `.rising`; selection is not a gate.
    func memoryGrowthListBadge(for rowPid: Int32) -> MemoryGrowthListBadge? {
        MemoryGrowthList.badge(
            page: selectedPage,
            rowPid: rowPid,
            seriesByPid: topMemorySeries
        )
    }
}
