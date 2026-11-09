import Foundation

/// Ordinary reveal id after the existing nil gate has opened.
/// A memory-page group hit uses that representative. A miss keeps `scrollTarget`.
/// Nil in stays nil and does not invent a pid. Does not write `selectedPid`.
enum MemoryRevealGroupRow {
    static func target(
        scrollTarget: Int32?,
        page: DashboardPage,
        grouping: Bool,
        visibleUngrouped: [ProcessRow]
    ) -> Int32? {
        guard let scrollTarget else { return nil }
        if let grouped = MemoryMagnitudeVisibleGroup.row(
            page: page,
            grouping: grouping,
            selectedPid: scrollTarget,
            visibleUngrouped: visibleUngrouped
        ) {
            return grouped.pid
        }
        return scrollTarget
    }
}
