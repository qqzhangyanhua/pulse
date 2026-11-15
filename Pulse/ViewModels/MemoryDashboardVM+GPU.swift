import AppKit
import Foundation

extension MemoryDashboardVM {
    /// AGX share only. Host utilization stays on every page and does not use this.
    var readsGPUShare: Bool { selectedPage == .gpu }

    /// Selected accelerator utilization for custom alerts. Nil is missing, not zero.
    var gpuAlertUtilizationPercent: Double? { core.gpuAlertUtilizationPercent }

    /// Active screens. Not a sample tick, and not the menu bar.
    var gpuDisplays: GPUDisplaysCard { core.gpuDisplays }

    /// Read on entry. While this page stays selected, screen-parameter changes read again.
    func syncGPUDisplayWatch() {
        guard selectedPage == .gpu else {
            endGPUDisplayWatch()
            return
        }
        guard gpuDisplayObserver == nil else { return }
        refreshGPUDisplays()
        gpuDisplayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshGPUDisplays()
            }
        }
    }

    func endGPUDisplayWatch() {
        if let gpuDisplayObserver {
            NotificationCenter.default.removeObserver(gpuDisplayObserver)
            self.gpuDisplayObserver = nil
        }
    }

    func refreshGPUDisplays() {
        mutateCore { $0.apply(gpuDisplays: HostGPUDisplayReader.read()) }
    }
}
