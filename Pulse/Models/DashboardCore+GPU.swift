import Foundation

extension DashboardCore {
    /// Leave and enter apply here, before the next sample. Same-page calls do not write.
    mutating func publishGPUPageTransition(from previous: DashboardPage, to page: DashboardPage) {
        let transition: GPUPageTransition
        if previous != .gpu, page == .gpu {
            transition = .justEntered
        } else if previous == .gpu, page != .gpu {
            transition = .justLeft
        } else {
            return
        }
        let frame: GPUFrameOutcome = transition == .justEntered && samplingFailed ? .failed : .pending
        gpuPage = GPUPageProjection.apply(
            frame: frame,
            sampledAt: nil,
            current: gpuPage,
            transition: transition
        )
    }

    /// Leave and enter apply here, before the next sample. Same-page calls do not write.
    mutating func publishChipTemperaturePageTransition(from previous: DashboardPage, to page: DashboardPage) {
        let transition: ChipTemperaturePageTransition
        if previous != .machine, page == .machine {
            transition = .justEntered
        } else if previous == .machine, page != .machine {
            transition = .justLeft
        } else {
            return
        }
        let frame: ChipTemperatureFrameOutcome = transition == .justEntered && samplingFailed ? .failed : .pending
        chipTemperature = ChipTemperaturePageProjection.apply(
            frame: frame,
            sampledAt: nil,
            current: chipTemperature,
            transition: transition
        )
    }

    /// Replaces the display card. Nil or empty is 「—」 for the whole card.
    /// Not called from the sampling frame, and not written into history.
    mutating func apply(gpuDisplays readings: [GPUDisplayReading]?) -> [DashboardEffect] {
        gpuDisplays = GPUDisplayProjection.present(readings)
        return []
    }

    /// Display list only. Utilization sampling stays on every page.
    func gpuDisplayWatchEffect(on page: DashboardPage) -> DashboardEffect {
        page == .gpu ? .startGPUDisplayWatch : .stopGPUDisplayWatch
    }
}
