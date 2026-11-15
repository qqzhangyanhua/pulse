import Foundation

extension MemoryDashboardVM {
    /// AGX share only. Host utilization stays on every page and does not use this.
    var readsGPUShare: Bool { selectedPage == .gpu }

    /// Selected accelerator utilization for custom alerts. Nil is missing, not zero.
    var gpuAlertUtilizationPercent: Double? { core.gpuAlertUtilizationPercent }

    /// GPU-share name. False when the pid has left the live process rows.
    func gpuShareNameOpensMemoryPage(_ pid: Int32) -> Bool {
        core.gpuShareNameOpensMemoryPage(pid)
    }

    /// Name tap. Present pid focuses memory, then selects. A missing pid does nothing.
    func openGPUShareProcess(_ pid: Int32) {
        mutateCore { $0.openGPUShareProcess(pid) }
    }
}
