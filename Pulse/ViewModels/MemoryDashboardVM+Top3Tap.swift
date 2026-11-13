import Foundation

extension MemoryDashboardVM: Top3TapHost {
    var windowedPids: Set<Int32> {
        WindowedAppLookup.pids(in: rows)
    }
}
