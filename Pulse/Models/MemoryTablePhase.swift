import Foundation

/// Memory-tab toolbar chrome. Session-only; not a Sampler or preference write.
enum MemoryRisingOnlyChrome {
    static let toggleTitle = "仅上涨"

    /// Only the memory tab draws this control. Other tabs keep the name field.
    static func showsToggle(page: DashboardPage) -> Bool {
        page == .memory
    }
}

/// Memory-table empty / ready gate. Sampling, list failure, and no-process stay first.
enum MemoryTablePhase: Equatable, Sendable {
    case sampling
    case processListFailed
    case failed
    case empty
    case nameFilterEmpty
    case risingOnlyEmpty
    case ready
}

enum MemoryTablePhaseResolver {
    static func resolve(
        page: DashboardPage,
        loadState: LoadState,
        processCount: Int,
        visibleCount: Int,
        hasActiveNameFilter: Bool,
        risingOnly: Bool,
        processListFailed: Bool
    ) -> MemoryTablePhase {
        if processCount == 0 {
            if loadState == .sampling { return .sampling }
            if processListFailed { return .processListFailed }
            if loadState == .failed { return .failed }
            return .empty
        }

        if visibleCount > 0 {
            return .ready
        }

        // Name filter wins over a pure rising empty, including the pair.
        if hasActiveNameFilter {
            return .nameFilterEmpty
        }

        if MemoryGrowthRisingFilter.isRisingOnlyEmpty(
            page: page,
            risingOnly: risingOnly,
            projectedCount: visibleCount
        ) {
            return .risingOnlyEmpty
        }

        return .empty
    }
}

/// Memory-page filter empties. Resource tabs keep `CPUPageCopy` and do not read this.
enum MemoryTableEmptyCopy {
    static let nameFilterTitle = "没有匹配的 App"
    static let nameFilterMessage = "清空名称和仅上涨过滤。"
    static let clearButtonTitle = "清空过滤"

    /// Twelve-period rising lines. Nil for every other phase, including name filter empty.
    static func risingOnlyLines(for phase: MemoryTablePhase) -> (title: String, message: String)? {
        guard phase == .risingOnlyEmpty else { return nil }
        return (
            MemoryGrowthRisingFilterCopy.emptyTitle,
            MemoryGrowthRisingFilterCopy.emptyMessage
        )
    }

    /// Clear-button copy only for the two filter empties. Other phases stay nil.
    static func filterEmptyLines(
        for phase: MemoryTablePhase
    ) -> (title: String, message: String, buttonTitle: String)? {
        switch phase {
        case .nameFilterEmpty:
            return (nameFilterTitle, nameFilterMessage, clearButtonTitle)
        case .risingOnlyEmpty:
            return (
                MemoryGrowthRisingFilterCopy.emptyTitle,
                MemoryGrowthRisingFilterCopy.emptyMessage,
                clearButtonTitle
            )
        case .sampling, .processListFailed, .failed, .empty, .ready:
            return nil
        }
    }
}

/// One-beat memory-page clear. Both inputs return to their defaults together.
/// Selection is the existing OFF identity: a kept pid stays, nil stays nil.
/// Does not sort, rewrite rows, or sample. Resource tabs do not call this.
struct MemoryPageFilterClear: Equatable, Sendable {
    var filter: String
    var risingOnly: Bool
    var selectedPid: Int32?

    static func project(
        filter: String,
        risingOnly: Bool,
        selectedPid: Int32?,
        rows: [ProcessRow],
        page: DashboardPage,
        seriesByPid: [Int32: [ChartSample]]
    ) -> MemoryPageFilterClear {
        // Always write both defaults, including when one input is already default.
        _ = (filter, risingOnly)
        return MemoryPageFilterClear(
            filter: "",
            risingOnly: false,
            selectedPid: MemoryGrowthRisingFilter.selectedPid(
                current: selectedPid,
                rows: rows,
                nameQuery: "",
                page: page,
                risingOnly: false,
                seriesByPid: seriesByPid
            )
        )
    }
}
