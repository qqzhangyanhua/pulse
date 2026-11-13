import Foundation

/// Side effects `MemoryDashboardVM` performs after a core mutation.
/// The core does not touch the sampler, the clock, or `ProcessInfo`.
enum DashboardEffect: Equatable {
    case requestRetryWake
    case applyRisingAndWindowedSelection
    /// Sampler `setSelectedPid` for the pid after list selection settles.
    case forwardSelectedPid(Int32?)
    /// `ProcessActions.terminate` when `force` is false, `forceTerminate` when true.
    /// `token` is nil when this pid did not issue a quit-store attempt.
    case terminate(pid: Int32, force: Bool, token: UInt64?)
    /// `ProcessActions.confirmForceQuit`. The Bool comes back through `resolveForceQuit`.
    case confirmForceQuit(displayName: String, generation: UInt64)
    /// SIGSTOP for a process this core just recorded as paused.
    case pauseProcess(pid: Int32)
    /// SIGCONT. The ledger record is already gone.
    case resumeProcess(pid: Int32)
    /// `setpriority(PRIO_PROCESS, pid, nice)`. Record the pid only when that call returns 0.
    case lowerPriority(pid: Int32)
    /// Restores the nice saved before the lower. The pid is already removed from the in-memory set.
    case restorePriority(pid: Int32)
    /// Quitting a paused process. The Bool comes back through `resolveResumeBeforeQuit`.
    case confirmResumeBeforeQuit(pid: Int32, displayName: String)
    /// Sampler `setMemoryPageSort` for the sort just written into the memory-page publication.
    case forwardMemoryPageSort(ProcessTableSort)
    /// Next tick reads the GPU page. Not a second sampler task.
    case setGPUSampling(on: Bool)
    case startMachineWatch
    case stopMachineWatch
    case startEnergyBatteryWatch
    case stopEnergyBatteryWatch
    case startSleepAssertionWatch
    case stopSleepAssertionWatch
    case startLaunchItemWatch
    case stopLaunchItemWatch
    /// `nettop` while the network page is selected. Not a sampler task.
    case startProcessNetworkWatch
    case stopProcessNetworkWatch
    /// Outbound public-IP lookup. Returned only from the query click.
    case lookupPublicIP(queriedAt: Date)
    /// System location prompt for the Wi-Fi name. Returned only from the allow click.
    case requestLocationAuthorization
}

/// Portable dashboard state. Mutations return effects the adapter performs.
/// `windowedPids` is an input; this type does not look up running applications.
struct DashboardCore {
    let ownPid: Int32

    private(set) var loadState: LoadState = .sampling
    private(set) var snapshot: MemorySnapshot?
    private(set) var systemCpuPercent: Double?
    /// Nil is missing, not zero. A failed sample does not clear it.
    private(set) var busiestCorePercent: Double?
    private(set) var hostNetworkRates = HostNetworkRates.missing
    private(set) var hostWiFi: HostWiFiReading?
    /// Nil until the first path push. Not a byte rate.
    var hostConnection: HostConnection?
    var ssidPermission = WiFiSSIDPermission.notDetermined
    /// Idle until the user clicks. Not sampled. Save does not query.
    /// A report includes the address only when that report turns IP redaction off.
    var publicIPRequest = PublicIPRequestState.idle
    private(set) var hostDiskRates = HostDiskRates.missing
    /// Host 换入 / 换出. Previous counters stay here. Not disk throughput.
    private(set) var memoryPage = MemoryPageState.initial
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
    /// Processes this session paused. Pid plus start time. Not a signal sender.
    var pausedLedger = PausedProcessLedger()
    /// Pids this session lowered successfully. Not stored. Nice dies with the process.
    var loweredPriorityPids: Set<Int32> = []
    var sidebarSubjectPid: Int32?
    private(set) var samplingFailed = false
    private(set) var usageHistory = UsageHistory()
    private(set) var cpuHistory = SystemCPUHistory()
    private(set) var networkHistory = SystemNetworkHistory()
    private(set) var diskHistory = SystemDiskHistory()
    var gpuPage = GPUPageState.initial
    /// Top GPU-share rows. Nil until a GPU-page read. Not the machine-wide curve.
    private(set) var gpuShare: GPUSharePresentation?
    /// Last on-page AGX sample. Off-page frames do not move it.
    private var gpuShareBaseline: GPUShareBaseline?
    var chipTemperature = ChipTemperaturePageState.initial
    /// Nil until the machine page's reader returns. Not cleared on leave.
    var machineFacts: MachineFacts?
    /// Nil hides the energy-page card, including a Mac with no internal battery.
    var energyBatteryCard: EnergyBatteryCard?
    var energyBatteryReading: EnergyBatteryReading?
    /// Held sleep assertions from the energy page. Empty until a successful read.
    var sleepAssertions: [SleepAssertionRow] = []
    /// Launch items from the machine page. Empty until that read. Not cleared on leave.
    var launchItems: [LaunchItemRow] = []
    /// Latest per-process download / upload. Empty off the network page. Nil rates are 「—」.
    var processNetworkRates: [Int32: ProcessNetworkRate] = [:]
    /// Last successful sample waiting for the adapter to write. Not a second curve.
    var historyDraft: HistoryDraft?
    /// Thermal and pressure changes not yet copied into `historyDraft`.
    var pendingHistoryEvents: [HistoryEvent] = []
    var lastHistoryPressure: PressureLevel?
    var lastHistoryThermalName: String?
    /// Nil unless the system is serious or critical.
    var thermalNotice: String?
    /// Top CPU processes while `thermalNotice` is showing. Nil hides the card.
    var thermalAdvice: ThermalAdvice?
    /// Seconds of the last published advice. Nil publishes on the next sample.
    var thermalAdviceLastUpdate: Double?
    private(set) var energyMachineHistory = EnergyMachineHistory()
    var selectedPid: Int32?
    var navigation = DashboardNavigation()
    /// Last sort published while the memory page was selected. Not the live table sort.
    private(set) var publication = MemoryPageSortPublication()
    var filter = ""
    var risingOnlyFilter = false
    var windowedOnlyFilter = false
    var groupedByApp = false
    /// One-shot memory Top card reveal. The next locate replaces it.
    var topAppLocateReveal: TopAppLocation.Reveal?
    /// Windowed-app pids supplied by the adapter. Not a live lookup.
    var windowedPids: Set<Int32> = []
    var selectedEnergyGeneration: Int?
    var energyRankingSpan = EnergyRankingSpan.oneMinute
    /// Toolbar label recorded from `MachineInfo`. Nil until the adapter notes it.
    private(set) var machineLabel: String?
    /// Host name recorded at start. Blank is nil. The adapter supplies it.
    private(set) var snapshotHostname: String?
    /// Projection of the sampling gate's retrying bit. Not a second retry flag.
    private(set) var isRetrying = false

    init(ownPid: Int32) {
        self.ownPid = ownPid
    }

    /// `Failure` is generic so this file does not name Darwin-only `HostMemoryError`.
    mutating func apply<Failure>(
        result: Result<SampledFrame, Failure>,
        accepted: Bool,
        page: DashboardPage
    ) -> [DashboardEffect] {
        let held = SamplingRetryApply.Held(
            loadState: loadState,
            samplingFailed: samplingFailed,
            processListFailed: processListFailed,
            hasSnapshot: snapshot != nil
        )
        historyDraft = nil
        let observation: ProcessQuitSession.Observation
        var applyFilters = false
        var thermalNow: Double?
        if !accepted {
            observation = ProcessQuitSession.Observation(freshnessInsufficient: true)
        } else {
            switch result {
            case .success(let frame):
                if let applied = SamplingRetryApply.apply(held, accepted: true, sampleSucceeded: true) {
                    commitSuccess(frame, applied: applied, page: page)
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
                    recordGPU(nodes: nil, failed: true, at: nil)
                    recordChip(sensors: nil, failed: true, at: nil, page: page)
                    observation = ProcessQuitSession.Observation(samplingFailed: true)
                } else {
                    observation = ProcessQuitSession.Observation(freshnessInsufficient: true)
                }
            }
        }
        return finishSample(
            observation: observation,
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

    /// Records the toolbar label. The adapter reads `MachineInfo` once at start.
    mutating func noteMachineLabel(_ label: String) {
        machineLabel = label
    }

    /// Records the host name for snapshot redaction. The adapter reads it once at start.
    mutating func noteSnapshotHostname(_ hostname: String) {
        let trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshotHostname = trimmed.isEmpty ? nil : trimmed
    }

    /// Records the sampling gate's retrying bit. Not a second retry flag.
    mutating func noteRetrying(_ retrying: Bool) {
        isRetrying = retrying
    }

    /// Replaces the windowed-app pid set supplied by the adapter.
    mutating func noteWindowedPids(_ pids: Set<Int32>) {
        windowedPids = pids
    }

    /// Memory page notifies Sampler with the live sort. Any other page leaves the publication alone.
    mutating func publishMemoryPageSort() -> [DashboardEffect] {
        switch publication.publishMemoryPageSort(navigation.sort, selectedPage: navigation.selectedPage) {
        case .notifySampler(let sort):
            return [.forwardMemoryPageSort(sort)]
        case .skip:
            return []
        }
    }

    private mutating func commitSuccess(
        _ frame: SampledFrame,
        applied: SamplingRetryApply.Held,
        page: DashboardPage
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
        recordGPU(nodes: frame.gpuNodes, failed: false, at: frame.snapshot.capturedAt)
        noteHistory(frame)
        recordGPUShare(clients: frame.gpuShareClients, rows: frame.rows, at: frame.snapshot.capturedAt, page: page)
        recordChip(sensors: frame.chipTemperatureSensors, failed: false, at: frame.snapshot.capturedAt, page: page)
        memoryPage = MemoryPageProjection.apply(
            counters: frame.hostPageCounters,
            sampledAt: frame.snapshot.capturedAt,
            current: memoryPage
        )
        rows = frame.rows
        energyWindowRates = frame.energyWindowRates
        energyHourRates = frame.energyHourRates
        exitedEnergyProcesses = frame.exitedEnergyProcesses
        energyLiveGenerations = frame.energyLiveGenerations
        energyMachineHistory = recordedEnergyHistory(
            rows: frame.rows,
            at: frame.snapshot.capturedAt,
            page: page
        )
        processListFailed = frame.processListFailed
        processPermissionFootnote = frame.permissionFootnote
        topMemorySeries = frame.topMemorySeries
        loadState = applied.loadState
    }

    private mutating func finishSample(
        observation: ProcessQuitSession.Observation,
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
            refreshThermalAdvice(now: thermalNow)
        }
        effects += absorbSampleSelection(effect)
        if applyFilters {
            effects.append(.applyRisingAndWindowedSelection)
        }
        return effects
    }

    /// Nil nodes means this tick did not read GPU. A missing percent is not stored as 0.
    private mutating func recordGPU(
        nodes: [GPUAcceleratorNode]?,
        failed: Bool,
        at date: Date?
    ) {
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

    /// Host utilization above is every page. This rank runs only while the GPU page is visible.
    private mutating func recordGPUShare(
        clients: [GPUShareClientSample]?,
        rows: [ProcessRow],
        at date: Date,
        page: DashboardPage
    ) {
        guard page == .gpu, let clients else { return }
        let step = GPUShareProjection.step(
            clients: clients,
            rows: rows,
            ownPid: ownPid,
            sampledAt: date,
            baseline: gpuShareBaseline
        )
        guard step.publish else { return }
        gpuShare = step.card
        gpuShareBaseline = step.baseline
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
        page: DashboardPage
    ) -> EnergyMachineHistory {
        var history = energyMachineHistory
        history.record(
            processWatts: processWatts(rows),
            batteryPercent: historyBatteryPercent(on: page),
            at: date
        )
        return history
    }

    private func processWatts(_ rows: [ProcessRow]) -> Double? {
        let known = rows.compactMap(\.energyWatts)
        return known.isEmpty ? nil : known.reduce(0, +)
    }
}
