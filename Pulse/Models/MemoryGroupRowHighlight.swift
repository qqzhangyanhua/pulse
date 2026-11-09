import Foundation

/// List-row paint for the memory page. A visible-group hit paints that combined
/// row. An empty lookup keeps pid equality. Does not write `selectedPid`.
enum MemoryGroupRowHighlight {
    static func highlighted(
        page: DashboardPage,
        grouping: Bool,
        selectedPid: Int32?,
        visibleUngrouped: [ProcessRow],
        rowPid: Int32
    ) -> Bool {
        if let grouped = MemoryMagnitudeVisibleGroup.row(
            page: page,
            grouping: grouping,
            selectedPid: selectedPid,
            visibleUngrouped: visibleUngrouped
        ) {
            return grouped.pid == rowPid
        }
        return selectedPid == rowPid
    }
}
