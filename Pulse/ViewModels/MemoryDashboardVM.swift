import Combine
import Foundation

@MainActor
final class MemoryDashboardVM: ObservableObject {
    @Published private(set) var core = DashboardCore(
        ownPid: ProcessInfo.processInfo.processIdentifier
    )
    var loadState: LoadState { core.loadState }
    var snapshot: MemorySnapshot? { core.snapshot }
    var systemCpuPercent: Double? { core.systemCpuPercent }
    /// Busiest core for the latest accepted frame. Nil is missing, not zero. Failure does not clear it.
    var busiestCorePercent: Double? { core.busiestCorePercent }
    var hostNetworkRates: HostNetworkRates { core.hostNetworkRates }
    @Published var hostConnection: HostConnection?
    @Published var ssidPermission = WiFiSSIDPermission.notDetermined
    var hostWiFi: HostWiFiReading? {
        get { core.hostWiFi }
        set { core.hostWiFi = newValue }
    }
    /// Idle until the user clicks. Not sampled and not saved.
    @Published var publicIPRequest = PublicIPRequestState.idle
    var hostDiskRates: HostDiskRates { core.hostDiskRates }
    var rows: [ProcessRow] { core.rows }
    /// Energy-page window rates for the latest accepted process list. Not written into `ProcessRow`.
    var energyWindowRates: [Int32: ProcessEnergyRates] { core.energyWindowRates }
    /// 1 分钟 or 1 小时. Views read `activeEnergyRates`, not either table directly.
    var energyRankingSpan: EnergyRankingSpan {
        get { core.energyRankingSpan }
        set { setEnergyRankingSpan(newValue) }
    }
    /// Minute-ledger rates for the latest accepted process list. Empty when that list failed.
    var energyHourRates: [Int32: ProcessEnergyRates] { core.energyHourRates }
    /// Sealed 1-hour generations. Empty when that list failed. Not part of `energyHourRates`.
    var exitedEnergyProcesses: [ExitedEnergyProcess] { core.exitedEnergyProcesses }
    var processListFailed: Bool { core.processListFailed }
    /// This frame's permission footnote. Empty when the process list failed.
    var processPermissionFootnote: String? { core.processPermissionFootnote }
    var detail: ProcessDetail? {
        get { core.detail }
        set { core.detail = newValue }
    }
    /// Bounded Top N=5 memory series. List rows look up `memoryGrowthListBadge(for:)`.
    var topMemorySeries: [Int32: [ChartSample]] { core.topMemorySeries }
    @Published private(set) var machineLabel: String?
    /// Host facts for the machine page. Nil until that page is opened. Not a sample frame.
    @Published var machineFacts: MachineFacts?
    /// Energy-page battery card. Nil hides it, including a Mac with no internal battery.
    @Published var energyBatteryCard: EnergyBatteryCard?
    /// Latest energy-page battery reading. Nil until that read; not a second poll.
    var energyBatteryReading: EnergyBatteryReading?
    /// The only session quit store. Phase and message are projections of this.
    var quitOutcome: ProcessQuitOutcome {
        get { core.quitOutcome }
        set { core.quitOutcome = newValue }
    }
    var sidebarSubjectPid: Int32? {
        get { core.sidebarSubjectPid }
        set { core.sidebarSubjectPid = newValue }
    }
    var samplingFailed: Bool { core.samplingFailed }
    /// Gate projection. Not a second retry flag.
    @Published private(set) var isRetrying = false
    var usageHistory: UsageHistory { core.usageHistory }
    var cpuHistory: SystemCPUHistory { core.cpuHistory }
    var networkHistory: SystemNetworkHistory { core.networkHistory }
    var diskHistory: SystemDiskHistory { core.diskHistory }
    /// GPU page readings. Samples taken off that page do not write this.
    var gpuPage: GPUPageState {
        get { core.gpuPage }
        set { core.gpuPage = newValue }
    }
    /// Machine-page chip temperature. Other pages do not write this.
    var chipTemperature: ChipTemperaturePageState {
        get { core.chipTemperature }
        set { core.chipTemperature = newValue }
    }
    var energyMachineHistory: EnergyMachineHistory { core.energyMachineHistory }
    /// Nil unless the system is serious or critical. Overviews read this; the menu bar does not.
    @Published var thermalNotice: String?
    /// Top CPU processes while `thermalNotice` is showing. Nil hides the card; the menu bar does not read this.
    @Published var thermalAdvice: ThermalAdvice?
    /// Seconds of the last published advice. Nil publishes on the next sample.
    var thermalAdviceLastUpdate: Double?
    var filter: String {
        get { core.filter }
        set { setFilter(newValue) }
    }
    /// Memory-tab only. Default OFF. Session-scoped; not a Sampler or preference write.
    var risingOnlyFilter: Bool {
        get { core.risingOnlyFilter }
        set { setRisingOnlyFilter(newValue) }
    }
    /// Memory-tab only. Default OFF. Keeps apps that can open a window.
    var windowedOnlyFilter: Bool {
        get { core.windowedOnlyFilter }
        set { setWindowedOnlyFilter(newValue) }
    }
    /// Memory, CPU, and energy display. Default OFF. Groups the current visible rows by name.
    var groupedByApp: Bool {
        get { core.groupedByApp }
        set { setGroupedByApp(newValue) }
    }
    /// One-shot memory Top card reveal. The next locate replaces it.
    @Published var topAppLocateReveal: TopAppLocation.Reveal?
    var navigation: DashboardNavigation { core.navigation }
    let snapshotExportStore = SnapshotExportStore()
    private var selectedEnergyGeneration: Int? {
        get { core.selectedEnergyGeneration }
        set { core.selectedEnergyGeneration = newValue }
    }
    private var energyLiveGenerations: [Int32: Int] { core.energyLiveGenerations }

    var selectedPid: Int32? {
        get { core.selectedPid }
        set { select(pid: newValue) }
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
        startWiFiSSIDWatch()
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

    var visibleRows: [ProcessRow] { core.visibleRows }

    /// Visible rows in the current table sort. Not stored and not published.
    var sortedRows: [ProcessRow] { core.sortedRows }

    /// Unfiltered `rows` ordered by the published memory-page sort.
    var menuBarPopover: MenuBarPopoverSnapshot { core.menuBarPopover }

    var selectedRow: ProcessRow? { core.selectedRow }

    var hasActiveFilter: Bool {
        !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

    /// 「打开 Pulse」 and dock reopen. Always memory; does not follow the last tab.
    /// Page-only: does not write `selectedPid`. Pair with `selectPidIfPresent` when a pid is known.
    func focusMemoryPage() {
        changePage { $0.focusMemoryPage() }
    }

    /// Select-if-present against the live `rows`. Missing / vanished pids are not written.
    func selectPidIfPresent(_ pid: Int32) {
        guard let accepted = ProcessSelection.acceptedPid(pid, in: rows) else { return }
        selectedPid = accepted
    }

    /// Process-list identity to reveal. Nil when nothing is selected or the pid left `rows`.
    var processListScrollTarget: Int32? { core.processListScrollTarget }

    /// Memory, CPU, energy, network, disk, machine, and GPU.
    func selectPage(_ page: DashboardPage) {
        changePage { $0.selectPage(page) }
    }

    func setTableSort(_ sort: ProcessTableSort) {
        updateCore { $0.setTableSort(sort) }
    }

    func select(pid: Int32?) {
        updateCore { $0.select(pid: pid) }
    }

    func setFilter(_ text: String) {
        updateCore { $0.setFilter(text) }
    }

    func setRisingOnlyFilter(_ on: Bool) {
        updateCore { $0.setRisingOnly(on) }
    }

    /// Looks up windowed apps only when the switch turns on.
    func setWindowedOnlyFilter(_ on: Bool) {
        guard on != windowedOnlyFilter else { return }
        let pids = on ? WindowedAppLookup.pids(in: rows) : windowedPids
        updateCore { $0.setWindowedOnly(on, windowedPids: pids) }
    }

    func setGroupedByApp(_ on: Bool) {
        updateCore { $0.setGroupedByApp(on) }
    }

    func setEnergyRankingSpan(_ span: EnergyRankingSpan) {
        updateCore { $0.setEnergyRankingSpan(span) }
    }

    func start() {
        guard !started else { return }
        started = true
        machineLabel = MachineInfo.toolbarLabel()
        updateCore { $0.publishMemoryPageSort() }
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

    /// Memory-page filter empties. Name, then rising, then windowed.
    func clearMemoryPageFilters() {
        updateCore { $0.clearMemoryPageFilters() }
    }

    func retrySampling() {
        var next = core
        let effects = next.retry()
        core = next
        perform(effects)
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
        let result = await sampler.sample(readGPU: selectedPage == .gpu, readChipTemperature: selectedPage == .machine)
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
        var next = core
        let effects = next.apply(
            result: result,
            accepted: accepted,
            page: next.selectedPage,
            batteryPercent: historyBatteryPercent,
            selectedPid: next.selectedPid
        )
        if accepted {
            next.windowedPids = WindowedAppLookup.pids(in: next.rows)
        }
        core = next
        perform(effects)
    }

    private func changePage(_ mutate: (inout DashboardCore) -> [DashboardEffect]) {
        let previous = selectedPage
        var next = core
        let effects = mutate(&next)
        core = next
        publishGPUTransition(from: previous, to: selectedPage)
        publishChipTemperatureTransition(from: previous, to: selectedPage)
        perform(effects)
    }

    private func updateCore(_ mutate: (inout DashboardCore) -> [DashboardEffect]) {
        var next = core
        let effects = mutate(&next)
        core = next
        perform(effects)
    }

    private func perform(_ effects: [DashboardEffect]) {
        for effect in effects {
            switch effect {
            case .requestRetryWake:
                samplingGate.requestManualRetry()
                isRetrying = samplingGate.retrying
                sleepTask?.cancel()
            case .refreshThermalAdvice(let now):
                refreshThermalAdvice(now: now)
            case .replaceListSelection(let pid):
                if selectedPid != pid, !keepsExitedEnergySelection(replacingWith: pid) {
                    selectedPid = pid
                }
            case .reconcileEnergySelection:
                reconcileEnergySelectionGeneration()
            case .replaceSidebarSubject(let pid):
                if sidebarSubjectPid != pid {
                    sidebarSubjectPid = pid
                }
            case .replaceDetail(let liveDetail):
                if detail != liveDetail {
                    detail = liveDetail
                }
            case .applyRisingAndWindowedSelection:
                updateCore { core in
                    core.applyRisingOnlySelection() + core.applyWindowedOnlySelection()
                }
            case .forwardSelectedPid(let pid):
                Task { await sampler.setSelectedPid(pid) }
            case .forwardMemoryPageSort(let sort):
                Task { await sampler.setMemoryPageSort(sort) }
            case .setGPUSampling:
                break
            case .startMachineWatch, .stopMachineWatch:
                syncMachineWatch()
            case .startEnergyBatteryWatch, .stopEnergyBatteryWatch:
                syncEnergyBatteryWatch()
            }
        }
    }
    var selectedEnergyExitedOnly: Bool {
        EnergyPage.blocksQuit(selectedPid: selectedPid, rememberedGeneration: selectedEnergyGeneration, liveRows: rows, liveGenerations: energyLiveGenerations, exited: exitedEnergyProcesses)
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
}
