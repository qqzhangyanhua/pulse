import Foundation

/// Locked empty-state copy for the next memory-tab toggle knife.
/// Title + secondary line; not the retired TECH sentence and not the long draft.
enum MemoryGrowthRisingFilterCopy {
    static let emptyTitle = "Top5 暂无上涨"
    static let emptyMessage = "其他进程未做趋势判断"
}

/// Memory-tab "rising only" table projection.
///
/// Pipeline: `rows` → name filter → (memory page AND ON) keep `badge != nil` →
/// hard-cap `MemoryGrowthTopSeries.pidLimit` → caller sorts last.
/// The keep predicate is the existing list badge, not a second growth math
/// and not the selected-pid detail ring.
enum MemoryGrowthRisingFilter {
    /// Name filter first. Rising keep is memory-page + ON only.
    static func apply(
        rows: [ProcessRow],
        nameQuery: String,
        page: DashboardPage,
        risingOnly: Bool,
        seriesByPid: [Int32: [ChartSample]]
    ) -> [ProcessRow] {
        let named = ProcessNameFilter.apply(rows, query: nameQuery)
        guard risingOnly, page == .memory else { return named }
        let rising = named.filter { row in
            MemoryGrowthList.badge(
                page: page,
                rowPid: row.pid,
                seriesByPid: seriesByPid
            ) != nil
        }
        return Array(rising.prefix(MemoryGrowthTopSeries.pidLimit))
    }

    /// Same keep as `apply`, then the caller's table-header sort.
    /// ON + memory still caps at Top N=5 after sort so extra rising series cannot leak.
    static func ordered(
        rows: [ProcessRow],
        nameQuery: String,
        page: DashboardPage,
        risingOnly: Bool,
        seriesByPid: [Int32: [ChartSample]],
        sort: ProcessTableSort
    ) -> [ProcessRow] {
        let projected = apply(
            rows: rows,
            nameQuery: nameQuery,
            page: page,
            risingOnly: risingOnly,
            seriesByPid: seriesByPid
        )
        let sorted = sort.ordered(projected)
        guard risingOnly, page == .memory else { return sorted }
        return Array(sorted.prefix(MemoryGrowthTopSeries.pidLimit))
    }

    /// Next-knife empty gate. Sampling / name-filter empties stay on their own paths.
    static func isRisingOnlyEmpty(
        page: DashboardPage,
        risingOnly: Bool,
        projectedCount: Int
    ) -> Bool {
        page == .memory && risingOnly && projectedCount == 0
    }

    /// ON + memory hides a selected pid that the list badge would not light.
    /// Name-filter hiding does not go through this path and keeps `current`.
    /// OFF does not resurrect a pid this switch already cleared.
    static func selectedPid(
        current: Int32?,
        rows: [ProcessRow],
        nameQuery: String,
        page: DashboardPage,
        risingOnly: Bool,
        seriesByPid: [Int32: [ChartSample]]
    ) -> Int32? {
        // Name filter is part of the table pipeline, not this clear. Callers
        // still pass it so the VM beat matches `visibleRows`.
        _ = nameQuery
        guard let current else { return nil }
        // Name-filter hide keeps `current` (existing quit-against-full-rows).
        // Only this switch, on the memory page, may clear a hidden pid.
        guard risingOnly, page == .memory else { return current }
        let projected = apply(
            rows: rows,
            nameQuery: "",
            page: page,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        return projected.contains(where: { $0.pid == current }) ? current : nil
    }
}
