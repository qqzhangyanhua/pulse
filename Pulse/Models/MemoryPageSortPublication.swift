import Foundation

/// MainActor-readable snapshot of the last sort published on the memory page.
///
/// This is the same `ProcessTableSort` the table already uses, not a second
/// menu-bar comparator and not `@Published lastMemorySort`. Resource-tab live
/// `tableSort` does not write it. Darwin-free so Linux `swift test` can cover
/// the publish guard; the VM holds one copy on the MainActor next knife.
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
}
