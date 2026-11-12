import Foundation

extension MemoryDashboardVM {
    /// Leave and enter apply here, before the next sample.
    func publishGPUTransition(from previous: DashboardPage, to page: DashboardPage) {
        let transition: GPUPageTransition
        if previous != .gpu, page == .gpu {
            transition = .justEntered
        } else if previous == .gpu, page != .gpu {
            transition = .justLeft
        } else {
            return
        }
        gpuPage = GPUPageProjection.apply(
            frame: .pending,
            sampledAt: nil,
            current: gpuPage,
            transition: transition
        )
    }

    /// Accepted main-tick frame. A skipped read (`nodes == nil`) does not invent empties.
    func recordGPUSample(nodes: [GPUAcceleratorNode]?, failed: Bool, at date: Date?) {
        guard selectedPage == .gpu else { return }
        let frame: GPUFrameOutcome
        if failed {
            frame = .failed
        } else if nodes != nil {
            frame = .succeeded
        } else {
            return
        }
        gpuPage = GPUPageProjection.apply(
            nodes: nodes ?? [],
            frame: frame,
            sampledAt: date,
            current: gpuPage,
            transition: .stayed
        )
    }
}
