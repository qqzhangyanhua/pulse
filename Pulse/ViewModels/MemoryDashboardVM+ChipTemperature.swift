import Foundation

extension MemoryDashboardVM {
    /// Leave and enter apply here, before the next sample.
    func publishChipTemperatureTransition(from previous: DashboardPage, to page: DashboardPage) {
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

    /// Accepted main-tick frame. A skipped read (`sensors == nil`) does not publish an empty success.
    func recordChipTemperatureSample(sensors: [ChipTemperatureSensor]?, failed: Bool, at date: Date?) {
        guard selectedPage == .machine else { return }
        let frame: ChipTemperatureFrameOutcome
        if failed {
            frame = .failed
        } else if sensors != nil {
            frame = .succeeded
        } else {
            return
        }
        chipTemperature = ChipTemperaturePageProjection.apply(
            sensors: sensors ?? [],
            frame: frame,
            sampledAt: date,
            current: chipTemperature,
            transition: .stayed
        )
    }
}
