import Combine
import Foundation

@MainActor
final class MemoryDashboardVM: ObservableObject {
    @Published private(set) var loadState: LoadState = .sampling
    @Published private(set) var snapshot: MemorySnapshot?
    @Published private(set) var systemCpuPercent: Double?
    /// Busiest core for the latest accepted frame. Nil is missing, not zero. Failure does not clear it.
    @Published private(set) var busiestCorePercent: Double?
    @Published private(set) var hostNetworkRates = HostNetworkRates.missing
    @Published private(set) var hostConnection: HostConnection?
    /// Idle until the user clicks. Not sampled and not saved.
    @Published var publicIPRequest = PublicIPRequestState.idle
    @Published private(set) var hostDiskRates = HostDiskRates.missing
    @Published private(set) var rows: [ProcessRow] = []
    /// Energy-page window rates for the latest accepted process list. Not written into `ProcessRow`.
    @Published private(set) var energyWindowRates: [Int32: ProcessEnergyRates] = [:]
    /// 1 分钟 or 1 小时. Views read `activeEnergyRates`, not either table directly.
    @Published var energyRankingSpan = EnergyRankingSpan.oneMinute
    /// Minute-ledger rates for the latest accepted process list. Empty when that list failed.
    @Published private(set) var energyHourRates: [Int32: ProcessEnergyRates] = [:]
    /// Sealed 1-hour generations. Empty when that list failed. Not part of `energyHourRates`.
    @Published private(set) var exitedEnergyProcesses: [ExitedEnergyProcess] = []
    @Published private(set) var processListFailed = false
    /// This frame's permission footnote. Empty when the process list failed.
    @Published private(set) var processPermissionFootnote: String?
    @Published private(set) var detail: ProcessDetail?
    /// Bounded Top N=5 memory series. List rows look up `memoryGrowthListBadge(for:)`.
    @Published private(set) var topMemorySeries: [Int32: [ChartSample]] = [:]
    @Published private(set) var machineLabel: String?
    /// Host facts for the machine page. Nil until that page is opened. Not a sample frame.
    @Published var machineFacts: MachineFacts?
    /// Energy-page battery card. Nil hides it, including a Mac with no internal battery.
    @Published var energyBatteryCard: EnergyBatteryCard?
    /// Latest energy-page battery reading. Nil until that read; not a second poll.
    var energyBatteryReading: EnergyBatteryReading?
    /// The only session quit store. Phase and message are projections of this.
    @Published var quitOutcome = ProcessQuitOutcome()
    @Published var sidebarSubjectPid: Int32?
    @Published private(set) var samplingFailed = false
    /// Gate projection. Not a second retry flag.
    @Published private(set) var isRetrying = false
    @Published private(set) var usageHistory = UsageHistory()
    @Published private(set) var cpuHistory = SystemCPUHistory()
    @Published private(set) var networkHistory = SystemNetworkHistory()
    @Published private(set) var diskHistory = SystemDiskHistory()
    /// GPU page readings. Samples taken off that page do not write this.
    @Published private(set) var gpuPage = GPUPageState.initial
    @Published private(set) var energyMachineHistory = EnergyMachineHistory()
    /// Nil unless the system is serious or critical. Overviews read this; the menu bar does not.
    @Published var thermalNotice: String?
    /// Top CPU processes while `thermalNotice` is showing. Nil hides the card; the menu bar does not read this.
    @Published var thermalAdvice: ThermalAdvice?
    /// Seconds of the last published advice. Nil publishes on the next sample.
    var thermalAdviceLastUpdate: Double?
    @Published var filter = ""
    /// Memory-tab only. Default OFF. Session-scoped; not a Sampler or preference write.
    @Published var risingOnlyFilter = false {
        didSet {
            guard oldValue != risingOnlyFilter else { return }
            applyRisingOnlySelection()
        }
    }
    /// Memory-tab only. Default OFF. Keeps apps that can open a window.
    @Published var windowedOnlyFilter = false {
        didSet {
            guard oldValue != windowedOnlyFilter else { return }
            applyWindowedOnlySelection()
        }
    }
    /// Memory and CPU display. Default OFF. Groups the current visible rows by name.
    @Published var groupedByApp = false {
        didSet {
            guard oldValue != groupedByApp else { return }
            applyGroupedByAppSelection()
        }
    }
    /// One-shot memory Top card reveal. The next locate replaces it.
    @Published var topAppLocateReveal: TopAppLocation.Reveal?
    @Published private(set) var navigation = DashboardNavigation()
    let snapshotExportStore = SnapshotExportStore()
    /// Last memory-page sort, readable on the MainActor. Not a second published sort field.
    private var publication = MemoryPageSortPublication()
    private var selectedEnergyGeneration: Int?
    private var energyLiveGenerations: [Int32: Int] = [:]

    @Published var selectedPid: Int32? {
        didSet {
            guard oldValue != selectedPid else { return }
            let effect = ProcessQuitSession.followListSelection(
                listSelectedPid: selectedPid,
                sidebarSubjectPid: sidebarSubjectPid,
                rows: rows
            )
            if selectedPid != effect.listSelectedPid {
                selectedPid = effect.listSelectedPid
                return
            }
            if sidebarSubjectPid != effect.sidebarSubjectPid {
                sidebarSubjectPid = effect.sidebarSubjectPid
            }
            captureEnergySelectionGeneration()
            detail = nil
            let pid = selectedPid
            Task { await sampler.setSelectedPid(pid) }
        }
    }
    private let sampler = MemorySampler()
    private var loopTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Error>?
    private var started = false
    private var samplingSession = SamplingSession()
    private var samplingClock = SamplingClock()
    private var samplingGate = SamplingRequestGate()
    var thermalObserver: NSObjectProtocol?
    var machineRefreshTask: Task<Void, Never>?
    var energyBatteryRefreshTask: Task<Void, Never>?
    var hostConnectionMonitor: HostConnectionMonitor?
    init() {
        beginThermalWatch()
        beginConnectionWatch()
    }
    // `isolated deinit` is Swift 6.2. Xcode 16.4 rejects it.
    deinit {
        MainActor.assumeIsolated {
            machineRefreshTask?.cancel()
            energyBatteryRefreshTask?.cancel()
            endThermalWatch()
            endConnectionWatch()
        }
    }

    var visibleRows: [ProcessRow] {
        let named = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: filter,
            page: selectedPage,
            risingOnly: risingOnlyFilter,
            seriesByPid: topMemorySeries
        )
        return WindowedAppFilter.apply(
            rows: named,
            page: selectedPage,
            windowedOnly: windowedOnlyFilter,
            windowedPids: { WindowedAppLookup.pids(in: rows) }
        )
    }

    /// Visible rows in the current table sort. Not stored and not published.
    var sortedRows: [ProcessRow] {
        if selectedPage == .energy {
            return EnergyPage.sorted(visibleRows, windowRates: activeEnergyRates, grouped: groupedByApp, sort: tableSort)
        }
        let projected = AppGroupProjection.apply(rows: visibleRows, grouped: groupedByApp && AppGroupChrome.applies(on: selectedPage))
        return tableSort.ordered(projected)
    }

    /// Strip B. Unfiltered `rows` ordered by the published memory-page sort.
    /// Does not read the name query, rising-only keep, or a resource-tab live `tableSort`.
    /// Passes the latest busiest core through; a failed sample still hides that sentence.
    var menuBarPopover: MenuBarPopoverSnapshot {
        MenuBarPopoverSnapshot.project(
            pressure: snapshot?.pressure,
            usedBytes: snapshot?.usedBytes,
            samplingFailed: samplingFailed,
            rows: rows,
            processListFailed: processListFailed,
            sort: publication.sort,
            busiestCorePercent: busiestCorePercent
        )
    }

    var selectedRow: ProcessRow? {
        guard let selectedPid else { return nil }
        return sortedRows.first { $0.pid == selectedPid } ?? rows.first { $0.pid == selectedPid }
    }

    var hasActiveFilter: Bool {
        !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedPage: DashboardPage { navigation.selectedPage }
    var tableSort: ProcessTableSort { navigation.sort }

    /// Live memory-page trend for the joint sidebar. A frozen absent card does not use it.
    var memoryGrowthSlot: MemoryGrowthSlot? {
        guard sidebar.showsLiveTrend else { return nil }
        return MemoryGrowthSidebar.slot(
            page: selectedPage,
            selectedPid: selectedPid,
            detailSeries: sidebar.detail?.memorySeries
        )
    }

    var sidebar: ProcessQuitSession.Sidebar {
        ProcessQuitSession.sidebar(
            quitOutcome,
            ProcessQuitSession.Context(
                listSelectedPid: selectedPid,
                sidebarSubjectPid: sidebarSubjectPid,
                rows: rows,
                liveDetail: detail
            )
        )
    }

    /// Per-row memory-tab list badge. Top5 ∩ `.rising`; selection is not a gate.
    func memoryGrowthListBadge(for rowPid: Int32) -> MemoryGrowthListBadge? {
        MemoryGrowthList.badge(
            page: selectedPage,
            rowPid: rowPid,
            seriesByPid: topMemorySeries
        )
    }

    /// 「打开 Pulse」 and dock reopen. Always memory; does not follow the last tab.
    /// Page-only: does not write `selectedPid`. Pair with `selectPidIfPresent` when a pid is known.
    func focusMemoryPage() {
        let previous = selectedPage
        var next = navigation
        next.focusMemoryPage()
        navigation = next
        publishGPUTransition(from: previous, to: selectedPage)
        publishMemoryPageSort()
        applyRisingOnlySelection()
        applyWindowedOnlySelection()
        syncMachineWatch()
        syncEnergyBatteryWatch()
    }

    /// Select-if-present against the live `rows`. Missing / vanished pids are not written.
    func selectPidIfPresent(_ pid: Int32) {
        guard let accepted = ProcessSelection.acceptedPid(pid, in: rows) else { return }
        selectedPid = accepted
    }

    /// Process-list identity to reveal. Nil when nothing is selected or the pid left `rows`.
    var processListScrollTarget: Int32? {
        ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows)
    }

    /// Memory, CPU, energy, network, disk, machine, and GPU.
    func selectPage(_ page: DashboardPage) {
        let previous = selectedPage
        var next = navigation
        next.select(page)
        navigation = next
        publishGPUTransition(from: previous, to: selectedPage)
        publishMemoryPageSort()
        applyRisingOnlySelection()
        applyWindowedOnlySelection()
        syncMachineWatch()
        syncEnergyBatteryWatch()
    }

    func setTableSort(_ sort: ProcessTableSort) {
        var next = navigation
        next.updateSort(sort)
        navigation = next
        publishMemoryPageSort()
    }

    func start() {
        guard !started else { return }
        started = true
        machineLabel = MachineInfo.toolbarLabel()
        publishMemoryPageSort()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let plan = self.samplingGate.plan(
                    clock: &self.samplingClock,
                    step: self.samplingSession.step
                )
                if plan.sample, let flight = plan.flight {
                    await self.tick(flight)
                }
                await self.sleepInterruptible(nanoseconds: plan.sleepNanoseconds)
            }
            guard let self else { return }
            self.finishSamplingLoop()
        }
    }

    /// App hook for scene phase. Background keeps the same sampler and only lengthens the interval.
    func setForeground(_ active: Bool) {
        samplingSession.setForeground(active)
    }

    /// Memory-page filter empties. Both existing fields are written on this turn,
    /// including when one of them is already the default.
    func clearMemoryPageFilters() {
        filter = ""
        risingOnlyFilter = false
        windowedOnlyFilter = false
    }

    func retrySampling() {
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
        samplingGate.requestManualRetry()
        isRetrying = samplingGate.retrying
        sleepTask?.cancel()
    }

    /// Only the memory-page sort drives Top 5 and the menu bar. Other tabs keep
    /// the last memory sort. Writes publication first, then forwards the same
    /// sort to Sampler without awaiting it for UI.
    private func publishMemoryPageSort() {
        switch publication.publishMemoryPageSort(tableSort, selectedPage: selectedPage) {
        case .notifySampler(let sort):
            Task { await sampler.setMemoryPageSort(sort) }
        case .skip:
            break
        }
    }

    private func finishSamplingLoop() {
        samplingGate.invalidate()
        isRetrying = samplingGate.retrying
        sleepTask?.cancel()
    }

    private func sleepInterruptible(nanoseconds: UInt64) async {
        let planned = nanoseconds
        let startedAt = ContinuousClock().now
        let task = Task<Void, Error> {
            try await Task.sleep(nanoseconds: planned)
        }
        sleepTask = task
        let completed = await withTaskCancellationHandler {
            do {
                try await task.value
                return true
            } catch {
                return false
            }
        } onCancel: {
            task.cancel()
        }
        sleepTask = nil
        let consumed: UInt64
        if completed {
            consumed = planned
        } else {
            consumed = nanosecondsElapsed(from: startedAt, to: ContinuousClock().now)
        }
        if let recordable = SamplingSleepWait.recordableNanoseconds(
            planned: planned,
            consumed: consumed,
            completed: completed,
            loopCancelled: Task.isCancelled
        ) {
            samplingClock.recordSleep(recordable)
        }
    }

    private func tick(_ flight: SamplingFlight) async {
        let result = await sampler.sample(readGPU: selectedPage == .gpu)
        if Task.isCancelled {
            samplingGate.invalidate()
            isRetrying = samplingGate.retrying
            return
        }
        let accepted = samplingGate.accept(flight)
        isRetrying = samplingGate.retrying
        applySample(result, accepted: accepted)
    }

    /// Every accepted frame, list failure, sampling failure, and stale flight
    /// reaches one presence observation. Model writes stay on the accepted paths.
    private func applySample(_ result: Result<SampledFrame, HostMemoryError>, accepted: Bool) {
        let held = SamplingRetryApply.Held(
            loadState: loadState,
            samplingFailed: samplingFailed,
            processListFailed: processListFailed,
            hasSnapshot: snapshot != nil
        )
        let observation: ProcessQuitSession.Observation
        var applyRisingOnly = false
        if !accepted {
            observation = ProcessQuitSession.Observation(freshnessInsufficient: true)
        } else {
            switch result {
            case .success(let frame):
                if let applied = SamplingRetryApply.apply(
                    held,
                    accepted: true,
                    sampleSucceeded: true
                ) {
                    samplingFailed = applied.samplingFailed
                    snapshot = frame.snapshot
                    systemCpuPercent = frame.systemCpuPercent
                    busiestCorePercent = frame.busiestCorePercent
                    hostNetworkRates = frame.hostNetworkRates
                    hostDiskRates = frame.hostDiskRates
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
                    recordGPUSample(nodes: frame.gpuNodes, failed: false, at: frame.snapshot.capturedAt)
                    rows = frame.rows
                    refreshThermalAdvice(now: frame.snapshot.capturedAt.timeIntervalSince1970)
                    energyWindowRates = frame.energyWindowRates
                    energyHourRates = frame.energyHourRates
                    exitedEnergyProcesses = frame.exitedEnergyProcesses
                    energyLiveGenerations = frame.energyLiveGenerations
                    energyMachineHistory = recordedEnergyHistory(rows: frame.rows, at: frame.snapshot.capturedAt)
                    processListFailed = frame.processListFailed
                    processPermissionFootnote = frame.permissionFootnote
                    topMemorySeries = frame.topMemorySeries
                    loadState = applied.loadState
                    observation = ProcessQuitSession.Observation(
                        rows: frame.rows,
                        liveDetail: frame.detail,
                        detailToFreeze: detail,
                        processListFailed: frame.processListFailed,
                        samplingFailed: false,
                        freshnessInsufficient: false,
                        usedBytes: frame.snapshot.usedBytes
                    )
                    applyRisingOnly = true
                } else {
                    observation = ProcessQuitSession.Observation(freshnessInsufficient: true)
                }
            case .failure:
                if let applied = SamplingRetryApply.apply(
                    held,
                    accepted: true,
                    sampleSucceeded: false
                ) {
                    samplingFailed = applied.samplingFailed
                    loadState = applied.loadState
                    recordGPUSample(nodes: nil, failed: true, at: nil)
                    observation = ProcessQuitSession.Observation(samplingFailed: true)
                } else {
                    observation = ProcessQuitSession.Observation(freshnessInsufficient: true)
                }
            }
        }
        var store = quitOutcome
        let effect = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: selectedPid,
            sidebarSubjectPid: sidebarSubjectPid,
            currentLiveDetail: detail,
            observation: observation
        )
        quitOutcome = store
        if selectedPid != effect.listSelectedPid, !keepsExitedEnergySelection(replacingWith: effect.listSelectedPid) {
            selectedPid = effect.listSelectedPid
        }
        reconcileEnergySelectionGeneration()
        if sidebarSubjectPid != effect.sidebarSubjectPid {
            sidebarSubjectPid = effect.sidebarSubjectPid
        }
        if detail != effect.liveDetail {
            detail = effect.liveDetail
        }
        if applyRisingOnly {
            applyRisingOnlySelection()
            applyWindowedOnlySelection()
        }
    }
    var selectedEnergyExitedOnly: Bool {
        EnergyPage.blocksQuit(selectedPid: selectedPid, rememberedGeneration: selectedEnergyGeneration, liveRows: rows, liveGenerations: energyLiveGenerations, exited: exitedEnergyProcesses)
    }
    private func captureEnergySelectionGeneration() {
        selectedEnergyGeneration = selectedPage == .energy ? selectedPid.flatMap { energyLiveGenerations[$0] } : nil
    }
    private func reconcileEnergySelectionGeneration() {
        let decision = EnergyPage.resolvedSelection(
            onEnergyPage: selectedPage == .energy,
            selectedPid: selectedPid,
            rememberedGeneration: selectedEnergyGeneration,
            liveRows: rows,
            liveGenerations: energyLiveGenerations
        )
        if selectedPid != decision.pid { selectedPid = decision.pid }
        selectedEnergyGeneration = decision.generation
    }
    func publishHostConnection(_ connection: HostConnection) { hostConnection = connection }
}
