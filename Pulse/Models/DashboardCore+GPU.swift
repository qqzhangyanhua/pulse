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
        if transition == .justLeft {
            gpuPage.powerSparkline.reset()
            gpuPage.frequencySparkline.reset()
        }
    }

    /// Power and frequency rings for this visit. Other pages do not append.
    /// The utilization curve is not this series.
    mutating func recordGPUSparklines(energy: EnergyModelReading?, at date: Date?, page: DashboardPage) {
        guard page == .gpu else { return }
        gpuPage.powerSparkline.record(percent: GPULiveSparkline.watts(energy?.gpuWatts), at: date)
        gpuPage.frequencySparkline.record(
            percent: GPULiveSparkline.hertz(energy?.gpuFrequency ?? .missing),
            at: date
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
}
