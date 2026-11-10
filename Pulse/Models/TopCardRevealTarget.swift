import Foundation

/// Scroll id for an already issued Top reveal.
/// A memory-page group hit uses that representative and does not require the
/// original pid to be a merged row id. A miss keeps today's `sortedRows` gate.
/// Nil means do not call `scrollTo`. Does not write `selectedPid`.
enum TopCardRevealTarget {
    static func scrollID(
        requestPid: Int32,
        page: DashboardPage,
        grouping: Bool,
        visibleUngrouped: [ProcessRow],
        sortedRows: [ProcessRow]
    ) -> Int32? {
        if let grouped = MemoryMagnitudeVisibleGroup.row(
            page: page,
            grouping: grouping,
            selectedPid: requestPid,
            visibleUngrouped: visibleUngrouped
        ) {
            return grouped.pid
        }
        guard sortedRows.contains(where: { $0.pid == requestPid }) else { return nil }
        return requestPid
    }
}
