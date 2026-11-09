import Foundation

/// Row for ⌘C and the Copy command after the text-focus check.
/// A memory-page group hit uses that combined row. Otherwise this is `selectedRow`.
/// Nil means the caller returns before writing the pasteboard. Does not write `selectedPid`.
enum MemoryGroupRowCopy {
    static func row(
        page: DashboardPage,
        grouping: Bool,
        selectedPid: Int32?,
        visibleUngrouped: [ProcessRow],
        sortedRows: [ProcessRow],
        rows: [ProcessRow]
    ) -> ProcessRow? {
        if let grouped = MemoryMagnitudeVisibleGroup.row(
            page: page,
            grouping: grouping,
            selectedPid: selectedPid,
            visibleUngrouped: visibleUngrouped
        ) {
            return grouped
        }
        guard let selectedPid else { return nil }
        return sortedRows.first { $0.pid == selectedPid } ?? rows.first { $0.pid == selectedPid }
    }
}
