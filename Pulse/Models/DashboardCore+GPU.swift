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

    /// Every accepted frame that read AGX, on every page. A failed process list does not seal.
    mutating func recordGPUTime(
        clients: [GPUShareClientSample]?,
        rows: [ProcessRow],
        listFailed: Bool,
        at date: Date
    ) {
        guard let clients else { return }
        let grouped = Dictionary(grouping: clients.filter { $0.pid != nil }) { $0.pid! }
        var live: [GPUTimeLiveSample] = []
        var seen = Set<Int32>()
        if !listFailed {
            for row in rows {
                guard seen.insert(row.pid).inserted, let start = row.startTimeSeconds else { continue }
                live.append(
                    GPUTimeLiveSample(
                        pid: row.pid,
                        startTimeSeconds: start,
                        name: row.name,
                        clients: grouped[row.pid] ?? []
                    )
                )
            }
        }
        gpuTimeLedger.advance(live: live, at: date, listSucceeded: !listFailed)
        gpuTime = GPUTimePresentation(
            rows: GPUTimeRanking.card(entries: gpuTimeLedger.entries, ownPid: ownPid)
        )
    }
}
