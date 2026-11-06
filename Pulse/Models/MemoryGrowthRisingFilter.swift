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
/// caller sorts last. The keep predicate is the existing list badge, whose
/// `seriesByPid` keys are the TopStore map (Sampler already caps N=5). This
/// type does not `prefix(5)` after the user's header sort.
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
        return named.filter { row in
            MemoryGrowthList.badge(
                page: page,
                rowPid: row.pid,
                seriesByPid: seriesByPid
            ) != nil
        }
    }

    /// Same keep as `apply`, then the caller's table-header sort. No second cap.
    static func ordered(
        rows: [ProcessRow],
        nameQuery: String,
        page: DashboardPage,
        risingOnly: Bool,
        seriesByPid: [Int32: [ChartSample]],
        sort: ProcessTableSort
    ) -> [ProcessRow] {
        sort.ordered(
            apply(
                rows: rows,
                nameQuery: nameQuery,
                page: page,
                risingOnly: risingOnly,
                seriesByPid: seriesByPid
            )
        )
    }

    /// Next-knife empty gate. Sampling / name-filter empties stay on their own paths.
    static func isRisingOnlyEmpty(
        page: DashboardPage,
        risingOnly: Bool,
        projectedCount: Int
    ) -> Bool {
        page == .memory && risingOnly && projectedCount == 0
    }

    /// ON + memory clears only when the current pid has no list badge.
    /// Name-filter hide of a rising pid keeps `current` (quit still targets full `rows`).
    /// OFF does not resurrect a pid this switch already cleared.
    static func selectedPid(
        current: Int32?,
        rows: [ProcessRow],
        nameQuery: String,
        page: DashboardPage,
        risingOnly: Bool,
        seriesByPid: [Int32: [ChartSample]]
    ) -> Int32? {
        // Table projection still name-filters first. Selection does not:
        // a rising pid hidden only by `nameQuery` stays selected.
        _ = (rows, nameQuery)
        guard let current else { return nil }
        guard risingOnly, page == .memory else { return current }
        let hasBadge = MemoryGrowthList.badge(
            page: page,
            rowPid: current,
            seriesByPid: seriesByPid
        ) != nil
        return hasBadge ? current : nil
    }
}
