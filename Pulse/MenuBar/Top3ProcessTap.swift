import Foundation

/// State the Top3 process-row scheduler reads and writes.
/// `MemoryDashboardVM` is the production host. A test double may stand in off Mac.
protocol Top3TapHost: AnyObject {
    var selectedPid: Int32? { get }
    var rows: [ProcessRow] { get }
    var filter: String { get set }
    var risingOnlyFilter: Bool { get set }
    var windowedOnlyFilter: Bool { get set }
    var groupedByApp: Bool { get }
    var navigation: DashboardNavigation { get }
    var topMemorySeries: [Int32: [ChartSample]] { get }
    var windowedPids: Set<Int32> { get }
    func selectPidIfPresent(_ pid: Int32)
    func focusMemoryPage()
}

/// What `MenuBarController.handlePopoverTap` runs for one Top3 process row.
/// Dismiss, then the existing select, then `focusMemoryPage` once, then activate once.
/// It does not call `onOpenPulse`.
enum Top3ProcessTap {
    struct Schedule: Equatable {
        var pageSwitches: Int
        var activations: Int
        var openPulseCalls: Int
    }

    static func perform(
        pid: Int32,
        host: Top3TapHost,
        dismiss: () -> Void,
        activate: () -> Void
    ) -> Schedule {
        dismiss()
        if ProcessSelection.acceptedPid(pid, in: host.rows) != nil {
            prepare(pid, on: host)
        }
        host.selectPidIfPresent(pid)
        host.focusMemoryPage()
        activate()
        return Schedule(pageSwitches: 1, activations: 1, openPulseCalls: 0)
    }

    /// Only the filters that would hide this pid. Grouping and sort stay put.
    private static func prepare(_ pid: Int32, on host: Top3TapHost) {
        let trimmed = host.filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let kept = ProcessNameFilter.apply(host.rows, query: host.filter)
            if !kept.contains(where: { $0.pid == pid }) {
                host.filter = ""
            }
        }
        if host.risingOnlyFilter {
            let badge = MemoryGrowthList.badge(
                page: .memory,
                rowPid: pid,
                seriesByPid: host.topMemorySeries
            )
            if badge == nil {
                host.risingOnlyFilter = false
            }
        }
        if host.windowedOnlyFilter, !host.windowedPids.contains(pid) {
            host.windowedOnlyFilter = false
        }
    }
}

/// 「打开 Pulse」 stays the shared entry: dismiss, then `onOpenPulse` once.
enum MenuBarOpenPulseTap {
    struct Schedule: Equatable {
        var openPulseCalls: Int
        var activations: Int
    }

    static func perform(dismiss: () -> Void, openPulse: () -> Void) -> Schedule {
        dismiss()
        openPulse()
        return Schedule(openPulseCalls: 1, activations: 0)
    }
}
