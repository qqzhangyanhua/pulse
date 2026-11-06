import Foundation

/// Result of one `publishMemoryPageSort` turn.
///
/// The VM writes publication first, then forwards the identical
/// `ProcessTableSort` to Sampler without awaiting it for UI.
enum MemoryPageSortSamplerHandoff: Equatable, Sendable {
    /// Memory page: publication was written; send this same value to `setMemoryPageSort`.
    case notifySampler(ProcessTableSort)
    /// Not on the memory page: publication unchanged; skip Sampler.
    case skip
}

/// MainActor-readable snapshot of the last sort published on the memory page.
///
/// This is the same `ProcessTableSort` the table already uses, not a second
/// menu-bar comparator and not `@Published lastMemorySort`. Resource-tab live
/// `tableSort` does not write it. Darwin-free so Linux `swift test` can cover
/// the publish guard and Sampler handoff; the VM holds one copy on the MainActor.
struct MemoryPageSortPublication: Equatable, Sendable {
    private(set) var sort: ProcessTableSort

    init(sort: ProcessTableSort = ProcessTableSort.defaultSort(for: .memory)) {
        self.sort = sort
    }

    /// Only `selectedPage == .memory` writes. CPU / network / disk publishes
    /// are no-ops, including a `start()` that is not on the memory page.
    mutating func publish(_ sort: ProcessTableSort, selectedPage: DashboardPage) {
        guard selectedPage == .memory else { return }
        self.sort = sort
    }

    /// Same guard the VM uses. Writes `sort` first, then returns that same
    /// value for Sampler. Resource-tab live `tableSort` yields `.skip`.
    mutating func publishMemoryPageSort(
        _ sort: ProcessTableSort,
        selectedPage: DashboardPage
    ) -> MemoryPageSortSamplerHandoff {
        guard selectedPage == .memory else { return .skip }
        publish(sort, selectedPage: selectedPage)
        return .notifySampler(sort)
    }
}
