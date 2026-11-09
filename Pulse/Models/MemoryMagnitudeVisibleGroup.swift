import Foundation

/// Memory-page magnitude row for the current visible same-name group.
/// Empty means the caller keeps the single-process row. Does not store a name,
/// write `selectedPid`, or sample.
enum MemoryMagnitudeVisibleGroup {
    static func row(
        page: DashboardPage,
        grouping: Bool,
        selectedPid: Int32?,
        visibleUngrouped: [ProcessRow]
    ) -> ProcessRow? {
        guard page == .memory, grouping, let selectedPid else { return nil }
        guard let selected = visibleUngrouped.first(where: { $0.pid == selectedPid }) else { return nil }
        let members = visibleUngrouped.filter { $0.name == selected.name }
        return AppGroupProjection.combine(members)
    }
}
