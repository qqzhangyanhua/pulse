import AppKit
import Foundation

extension MemoryDashboardVM {
    /// Selected accelerator utilization for custom alerts. Nil is missing, not zero.
    var gpuAlertUtilizationPercent: Double? { core.gpuAlertUtilizationPercent }

    /// Last hour of per-process GPU time. Nil before the first AGX read.
    var gpuTime: GPUTimePresentation? { core.gpuTime }

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

    /// GPU-share name. False when the pid has left the live process rows.
    func gpuShareNameOpensMemoryPage(_ pid: Int32) -> Bool {
        core.gpuShareNameOpensMemoryPage(pid)
    }

    /// Name tap. Present pid focuses memory, then selects. A missing pid does nothing.
    func openGPUShareProcess(_ pid: Int32) {
        mutateCore { $0.openGPUShareProcess(pid) }
    }
}
