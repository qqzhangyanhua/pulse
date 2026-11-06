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

        if MemoryGrowthRisingFilter.isRisingOnlyEmpty(
            page: page,
            risingOnly: risingOnly,
            projectedCount: visibleCount
        ) {
            return .risingOnlyEmpty
        }

        if hasActiveNameFilter {
            return .nameFilterEmpty
        }

        return .empty
    }
}

/// ON empty is two existing copy lines. Other phases keep their own views.
enum MemoryTableEmptyCopy {
    static func risingOnlyLines(for phase: MemoryTablePhase) -> (title: String, message: String)? {
        guard phase == .risingOnlyEmpty else { return nil }
        return (
            MemoryGrowthRisingFilterCopy.emptyTitle,
            MemoryGrowthRisingFilterCopy.emptyMessage
        )
    }
}
