import Foundation

/// What one accepted sample hands the GPU. `DashboardCore` builds it from `SampledFrame`.
struct GPUFrameInput {
    /// Nil when this tick did not read GPU.
    var nodes: [GPUAcceleratorNode]?
    /// Nil when that static read returned none.
    var recommendedMaxWorkingSetBytes: UInt64?
    /// Energy Model for the page that asked. Nil off the GPU page, or before the first delta.
    var energy: EnergyModelReading?
    /// Nil when this tick did not read AGX clients. Empty was read and had no client.
    var shareClients: [GPUShareClientSample]?
    var rows: [ProcessRow]
    var processListFailed: Bool
    var sampledAt: Date
}

/// Everything Pulse holds about the GPU, and the rules for which page records what.
/// Every page: utilization, its curve, the alert percent, and the GPU-time ledger.
/// GPU page only: share, frequency distribution, power, frequency, and their live sparklines.
struct GPUState: Equatable {
    let ownPid: Int32
    private(set) var page = GPUPageState.initial
    /// Selected-node utilization for alerts. Nil when this tick did not read GPU. Not zero, and not the page's previous percent.
    private(set) var alertUtilizationPercent: Double?
    /// Top GPU-share rows. Nil until a GPU-page read. Not the machine-wide curve.
    private(set) var share: GPUSharePresentation?
    /// Frequency-distribution card. Only a GPU-page sample writes it. Not saved.
    private(set) var frequencyDistribution: GPUFrequencyDistribution = .missing
    /// Top GPU-time rows. Nil until a frame includes an AGX client read.
    private(set) var time: GPUTimePresentation?
    /// Active screens for the GPU page. Not written by the sample frame.
    private(set) var displays = GPUDisplaysCard.missing
    /// GPU power for this visit. Nil is 「—」, not 0. Cleared on leave.
    private(set) var watts: Double?
    /// GPU frequency for this visit. Cleared to missing on leave.
    private(set) var frequency: GPUFrequency = .missing
    /// Last on-page AGX sample. Off-page frames do not move it.
    private var shareBaseline: GPUShareBaseline?
    /// Hour ledger fed on every page. Not the share baseline, and not on disk.
    private var timeLedger = GPUTimeMinuteLedger()

    init(ownPid: Int32) {
        self.ownPid = ownPid
    }

    var powerText: String { EnergyModelCopy.gpuPowerReading(watts) }

    var frequencyText: String { EnergyModelCopy.gpuFrequencyReading(frequency) }

    var powerLine: String { EnergyModelCopy.gpuPowerLine(watts: watts) }

    var frequencyLine: String { EnergyModelCopy.gpuFrequencyLine(frequency) }

    /// One accepted successful frame, sampled while `selected` was the page.
    mutating func absorb(_ input: GPUFrameInput, page selected: DashboardPage) {
        let onPage = selected == .gpu
        if onPage {
            // Off-page frames keep the last card. On the GPU page, no sample delta is 「—」.
            frequencyDistribution = input.energy?.gpuFrequencyDistribution ?? .missing
        }
        recordUtilization(
            nodes: input.nodes,
            recommendedMaxWorkingSetBytes: input.recommendedMaxWorkingSetBytes,
            failed: false,
            at: input.sampledAt
        )
        if onPage {
            recordPowerAndFrequency(energy: input.energy, at: input.sampledAt)
            recordShare(clients: input.shareClients, rows: input.rows, at: input.sampledAt)
        }
        recordTime(
            clients: input.shareClients,
            rows: input.rows,
            listFailed: input.processListFailed,
            at: input.sampledAt
        )
    }

    /// An accepted failed sample, on any page.
    mutating func absorbFailure() {
        recordUtilization(nodes: nil, failed: true, at: nil)
    }

    /// Leave and enter apply here, before the next sample. Same-page calls do not write.
    mutating func transition(from previous: DashboardPage, to next: DashboardPage, samplingFailed: Bool) {
        let transition: GPUPageTransition
        if previous != .gpu, next == .gpu {
            transition = .justEntered
        } else if previous == .gpu, next != .gpu {
            transition = .justLeft
        } else {
            return
        }
        let frame: GPUFrameOutcome = transition == .justEntered && samplingFailed ? .failed : .pending
        page = GPUPageProjection.apply(
            frame: frame,
            sampledAt: nil,
            current: page,
            transition: transition
        )
        if transition == .justLeft {
            page.powerSparkline.reset()
            page.frequencySparkline.reset()
            watts = nil
            frequency = .missing
        }
    }

    /// Replaces the display card. Nil or empty is 「—」 for the whole card.
    /// Not called from the sampling frame, and not written into history.
    mutating func apply(displays readings: [GPUDisplayReading]?) {
        displays = GPUDisplayProjection.present(readings)
    }

    /// Nil nodes means this tick did not read GPU. A missing percent is not stored as 0.
    private mutating func recordUtilization(
        nodes: [GPUAcceleratorNode]?,
        recommendedMaxWorkingSetBytes: UInt64? = nil,
        failed: Bool,
        at date: Date?
    ) {
        let frame: GPUFrameOutcome
        if failed {
            frame = .failed
        } else if nodes != nil {
            frame = .succeeded
        } else {
            alertUtilizationPercent = nil
            return
        }
        page = GPUPageProjection.apply(
            nodes: nodes ?? [],
            recommendedMaxWorkingSetBytes: recommendedMaxWorkingSetBytes,
            frame: frame,
            sampledAt: date,
            current: page,
            transition: .stayed
        )
        alertUtilizationPercent = failed ? nil : AlertGPUReading.percent(from: nodes)
    }

    /// Power and frequency rings for this visit. The utilization curve is not this series.
    private mutating func recordPowerAndFrequency(energy: EnergyModelReading?, at date: Date) {
        watts = energy?.gpuWatts
        frequency = energy?.gpuFrequency ?? .missing
        page.powerSparkline.record(percent: GPULiveSparkline.watts(watts), at: date)
        page.frequencySparkline.record(percent: GPULiveSparkline.hertz(frequency), at: date)
    }

    /// Host utilization is every page. This rank runs only while the GPU page is visible.
    private mutating func recordShare(clients: [GPUShareClientSample]?, rows: [ProcessRow], at date: Date) {
        guard let clients else { return }
        let step = GPUShareProjection.step(
            clients: clients,
            rows: rows,
            ownPid: ownPid,
            sampledAt: date,
            baseline: shareBaseline
        )
        guard step.publish else { return }
        share = step.card
        shareBaseline = step.baseline
    }

    /// Every accepted frame that read AGX, on every page. A failed process list does not seal.
    private mutating func recordTime(
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
        timeLedger.advance(live: live, at: date, listSucceeded: !listFailed)
        time = GPUTimePresentation(
            rows: GPUTimeRanking.card(entries: timeLedger.entries, ownPid: ownPid)
        )
    }
}
