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
