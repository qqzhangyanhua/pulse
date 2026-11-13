import Foundation

extension MemoryDashboardVM: Top3TapHost {
    var windowedPids: Set<Int32> { core.windowedPids }
}
