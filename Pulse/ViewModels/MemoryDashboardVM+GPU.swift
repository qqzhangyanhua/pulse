import Foundation

extension MemoryDashboardVM {
    /// AGX share only. Host utilization stays on every page and does not use this.
    var readsGPUShare: Bool { selectedPage == .gpu }
}
