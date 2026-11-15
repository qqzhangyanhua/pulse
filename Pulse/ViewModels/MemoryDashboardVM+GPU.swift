import Foundation

extension MemoryDashboardVM {
    /// Selected accelerator utilization for custom alerts. Nil is missing, not zero.
    var gpuAlertUtilizationPercent: Double? { core.gpuAlertUtilizationPercent }

    /// Last hour of per-process GPU time. Nil before the first AGX read.
    var gpuTime: GPUTimePresentation? { core.gpuTime }
}
