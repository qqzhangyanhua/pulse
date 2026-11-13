import Foundation

/// Side effects `MemoryDashboardVM` performs after a core mutation.
/// The core does not touch the sampler, the clock, or `ProcessInfo`.
enum DashboardEffect: Equatable {
    case requestRetryWake
    case refreshThermalAdvice(now: Double)
    case replaceListSelection(Int32?)
    case reconcileEnergySelection
    case replaceSidebarSubject(Int32?)
    case replaceDetail(ProcessDetail?)
    case applyRisingAndWindowedSelection
}

/// Portable dashboard state for one sampling result or a manual retry.
/// `selectedPid` stays on the adapter so its existing `didSet` still runs.
struct DashboardCore {
    let ownPid: Int32

    private(set) var loadState: LoadState = .sampling
    private(set) var snapshot: MemorySnapshot?
    private(set) var systemCpuPercent: Double?
    /// Nil is missing, not zero. A failed sample does not clear it.
    private(set) var busiestCorePercent: Double?
    private(set) var hostNetworkRates = HostNetworkRates.missing
    var hostWiFi: HostWiFiReading?
    private(set) var hostDiskRates = HostDiskRates.missing
    private(set) var rows: [ProcessRow] = []
    private(set) var energyWindowRates: [Int32: ProcessEnergyRates] = [:]
    private(set) var energyHourRates: [Int32: ProcessEnergyRates] = [:]
    private(set) var exitedEnergyProcesses: [ExitedEnergyProcess] = []
    private(set) var energyLiveGenerations: [Int32: Int] = [:]
    private(set) var processListFailed = false
    private(set) var processPermissionFootnote: String?
    var detail: ProcessDetail?
    private(set) var topMemorySeries: [Int32: [ChartSample]] = [:]
    var quitOutcome = ProcessQuitOutcome()
    var sidebarSubjectPid: Int32?
    private(set) var samplingFailed = false
    private(set) var usageHistory = UsageHistory()
    private(set) var cpuHistory = SystemCPUHistory()
    private(set) var networkHistory = SystemNetworkHistory()
    private(set) var diskHistory = SystemDiskHistory()
    var gpuPage = GPUPageState.initial
    var chipTemperature = ChipTemperaturePageState.initial
    private(set) var energyMachineHistory = EnergyMachineHistory()

    init(ownPid: Int32) {
        self.ownPid = ownPid
    }

    /// `Failure` is generic so this file does not name Darwin-only `HostMemoryError`.
    mutating func apply<Failure>(
        result: Result<SampledFrame, Failure>,
        accepted: Bool,
        page: DashboardPage,
        batteryPercent: Double?,
        selectedPid: Int32?
    ) -> [DashboardEffect] {
        let held = SamplingRetryApply.Held(
            loadState: loadState,
            samplingFailed: samplingFailed,
            processListFailed: processListFailed,
            hasSnapshot: snapshot != nil
        )
        let observation: ProcessQuitSession.Observation
        var applyFilters = false
        var thermalNow: Double?
        if !accepted {
            observation = ProcessQuitSession.Observation(freshnessInsufficient: true)
        } else {
            switch result {
            case .success(let frame):
                if let applied = SamplingRetryApply.apply(held, accepted: true, sampleSucceeded: true) {
                    commitSuccess(frame, applied: applied, page: page, batteryPercent: batteryPercent)
                    thermalNow = frame.snapshot.capturedAt.timeIntervalSince1970
                    observation = ProcessQuitSession.Observation(
                        rows: frame.rows,
                        liveDetail: frame.detail,
                        detailToFreeze: detail,
                        processListFailed: frame.processListFailed,
                        samplingFailed: false,
                        freshnessInsufficient: false,
                        usedBytes: frame.snapshot.usedBytes
                    )
                    applyFilters = true
                } else {
                    observation = ProcessQuitSession.Observation(freshnessInsufficient: true)
                }
            case .failure:
                if let applied = SamplingRetryApply.apply(held, accepted: true, sampleSucceeded: false) {
                    samplingFailed = applied.samplingFailed
                    loadState = applied.loadState
                    recordGPU(nodes: nil, failed: true, at: nil, page: page)
                    recordChip(sensors: nil, failed: true, at: nil, page: page)
                    observation = ProcessQuitSession.Observation(samplingFailed: true)
                } else {
                    observation = ProcessQuitSession.Observation(freshnessInsufficient: true)
                }
            }
        }
        return finishSample(
            observation: observation,
            selectedPid: selectedPid,
            applyFilters: applyFilters,
            thermalNow: thermalNow
        )
    }

    /// Keeps the failure phase and flags. The adapter performs `requestRetryWake`.
    mutating func retry() -> [DashboardEffect] {
        let held = SamplingRetryApply.Held(
            loadState: loadState,
            samplingFailed: samplingFailed,
            processListFailed: processListFailed,
            hasSnapshot: snapshot != nil
        )
        let next = SamplingRetryApply.afterManualRetry(held)
        loadState = next.loadState
        samplingFailed = next.samplingFailed
        processListFailed = next.processListFailed
        return [.requestRetryWake]
    }

    private mutating func commitSuccess(
        _ frame: SampledFrame,
        applied: SamplingRetryApply.Held,
        page: DashboardPage,
        batteryPercent: Double?
    ) {
        samplingFailed = applied.samplingFailed
        snapshot = frame.snapshot
        systemCpuPercent = frame.systemCpuPercent
        busiestCorePercent = frame.busiestCorePercent
        hostNetworkRates = frame.hostNetworkRates
        hostDiskRates = frame.hostDiskRates
        hostWiFi = frame.hostWiFi
        var nextUsage = usageHistory
        nextUsage.record(frame.snapshot)
        usageHistory = nextUsage
        var nextCPU = cpuHistory
        nextCPU.record(percent: frame.systemCpuPercent, at: frame.snapshot.capturedAt)
        cpuHistory = nextCPU
        var nextNetwork = networkHistory
        nextNetwork.record(rates: frame.hostNetworkRates, at: frame.snapshot.capturedAt)
        networkHistory = nextNetwork
        var nextDisk = diskHistory
        nextDisk.record(rates: frame.hostDiskRates, at: frame.snapshot.capturedAt)
        diskHistory = nextDisk
        recordGPU(nodes: frame.gpuNodes, failed: false, at: frame.snapshot.capturedAt, page: page)
        recordChip(sensors: frame.chipTemperatureSensors, failed: false, at: frame.snapshot.capturedAt, page: page)
        rows = frame.rows
        energyWindowRates = frame.energyWindowRates
        energyHourRates = frame.energyHourRates
        exitedEnergyProcesses = frame.exitedEnergyProcesses
        energyLiveGenerations = frame.energyLiveGenerations
        energyMachineHistory = recordedEnergyHistory(
            rows: frame.rows,
            at: frame.snapshot.capturedAt,
            page: page,
            batteryPercent: batteryPercent
        )
        processListFailed = frame.processListFailed
        processPermissionFootnote = frame.permissionFootnote
        topMemorySeries = frame.topMemorySeries
        loadState = applied.loadState
    }

    private mutating func finishSample(
        observation: ProcessQuitSession.Observation,
        selectedPid: Int32?,
        applyFilters: Bool,
        thermalNow: Double?
    ) -> [DashboardEffect] {
        var store = quitOutcome
        let effect = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: selectedPid,
            sidebarSubjectPid: sidebarSubjectPid,
            currentLiveDetail: detail,
            observation: observation
        )
        quitOutcome = store
        var effects: [DashboardEffect] = []
        if let thermalNow {
            effects.append(.refreshThermalAdvice(now: thermalNow))
        }
        effects.append(.replaceListSelection(effect.listSelectedPid))
        effects.append(.reconcileEnergySelection)
        effects.append(.replaceSidebarSubject(effect.sidebarSubjectPid))
        effects.append(.replaceDetail(effect.liveDetail))
        if applyFilters {
            effects.append(.applyRisingAndWindowedSelection)
        }
        return effects
    }

    private mutating func recordGPU(
        nodes: [GPUAcceleratorNode]?,
        failed: Bool,
        at date: Date?,
        page: DashboardPage
    ) {
        guard page == .gpu else { return }
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

    private mutating func recordChip(
        sensors: [ChipTemperatureSensor]?,
        failed: Bool,
        at date: Date?,
        page: DashboardPage
    ) {
        guard page == .machine else { return }
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

    private func recordedEnergyHistory(
        rows: [ProcessRow],
        at date: Date,
        page: DashboardPage,
        batteryPercent: Double?
    ) -> EnergyMachineHistory {
        var history = energyMachineHistory
        history.record(
            processWatts: processWatts(rows),
            batteryPercent: page == .energy ? batteryPercent : nil,
            at: date
        )
        return history
    }

    private func processWatts(_ rows: [ProcessRow]) -> Double? {
        let known = rows.compactMap(\.energyWatts)
        return known.isEmpty ? nil : known.reduce(0, +)
    }
}
