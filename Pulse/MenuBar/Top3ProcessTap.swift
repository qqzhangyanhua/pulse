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

    /// Today's process-row semantics. Filter preparation is not in this body yet.
    static func perform(
        pid: Int32,
        host: Top3TapHost,
        dismiss: () -> Void,
        activate: () -> Void
    ) -> Schedule {
        dismiss()
        host.selectPidIfPresent(pid)
        host.focusMemoryPage()
        activate()
        return Schedule(pageSwitches: 1, activations: 1, openPulseCalls: 0)
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
