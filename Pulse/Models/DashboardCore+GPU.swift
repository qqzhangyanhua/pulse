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

    /// GPU-share name. Only a pid still in the live process rows can open the memory page.
    func gpuShareNameOpensMemoryPage(_ pid: Int32) -> Bool {
        ProcessSelection.acceptedPid(pid, in: rows) != nil
    }

    /// Name tap. Present pid: `focusMemoryPage`, then select-if-present. Filters stay.
    /// A missing pid changes nothing.
    mutating func openGPUShareProcess(_ pid: Int32) -> [DashboardEffect] {
        guard let accepted = ProcessSelection.acceptedPid(pid, in: rows) else { return [] }
        var effects = focusMemoryPage()
        effects += select(pid: accepted)
        return effects
    }
}
