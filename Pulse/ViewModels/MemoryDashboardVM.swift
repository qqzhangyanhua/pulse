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
    var hostConnection: HostConnection? { core.hostConnection }
    var ssidPermission: WiFiSSIDPermission { core.ssidPermission }
    var hostWiFi: HostWiFiReading? { core.hostWiFi }
    /// Idle until the user clicks. Not sampled and not saved.
    var publicIPRequest: PublicIPRequestState { core.publicIPRequest }
    var hostDiskRates: HostDiskRates { core.hostDiskRates }
    /// Host 换入 / 换出. Nil rates are 「—」, not zero. Not a disk rate.
    var memoryPage: MemoryPageState { core.memoryPage }
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
    var detail: ProcessDetail? { core.detail }
    /// Bounded Top N=5 memory series. List rows look up `memoryGrowthListBadge(for:)`.
    var topMemorySeries: [Int32: [ChartSample]] { core.topMemorySeries }
    var machineLabel: String? { core.machineLabel }
    /// Host facts for the machine page. Nil until that page is opened. Not a sample frame.
    var machineFacts: MachineFacts? { core.machineFacts }
    /// Energy-page battery card. Nil hides it, including a Mac with no internal battery.
    var energyBatteryCard: EnergyBatteryCard? { core.energyBatteryCard }
    /// Latest energy-page battery reading. Nil until that read; not a second poll.
    var energyBatteryReading: EnergyBatteryReading? { core.energyBatteryReading }
    /// Sleep assertions for the energy-page card. Stored on the core, not here.
    var sleepAssertions: [SleepAssertionRow] { core.sleepAssertions }
    /// Launch items for the machine page. Stored on the core, not here.
    var launchItems: [LaunchItemRow] { core.launchItems }
    /// The only session quit store. Phase and message are projections of this.
    var quitOutcome: ProcessQuitOutcome { core.quitOutcome }
    var sidebarSubjectPid: Int32? { core.sidebarSubjectPid }
    var samplingFailed: Bool { core.samplingFailed }
    /// Gate projection. Not a second retry flag.
    var isRetrying: Bool { core.isRetrying }
    var usageHistory: UsageHistory { core.usageHistory }
    var cpuHistory: SystemCPUHistory { core.cpuHistory }
    var networkHistory: SystemNetworkHistory { core.networkHistory }
    var diskHistory: SystemDiskHistory { core.diskHistory }
    /// GPU page readings. Samples taken off that page do not write this.
    var gpuPage: GPUPageState { core.gpuPage }
    /// Top GPU-share rows. Ranked only while the GPU page is visible.
    var gpuShare: GPUSharePresentation? { core.gpuShare }
    /// Machine-page chip temperature. Other pages do not write this.
    var chipTemperature: ChipTemperaturePageState { core.chipTemperature }
    var energyMachineHistory: EnergyMachineHistory { core.energyMachineHistory }
    /// Nil unless the system is serious or critical. Overviews read this; the menu bar does not.
    var thermalNotice: String? { core.thermalNotice }
    /// Top CPU processes while `thermalNotice` is showing. Nil hides the card; the menu bar does not read this.
    var thermalAdvice: ThermalAdvice? { core.thermalAdvice }
    /// Seconds of the last published advice. Nil publishes on the next sample.
    var thermalAdviceLastUpdate: Double? { core.thermalAdviceLastUpdate }
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
    var navigation: DashboardNavigation { core.navigation }
    let snapshotExportStore = SnapshotExportStore()

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
    var sleepAssertionRefreshTask: Task<Void, Never>?
    var launchItemRefreshTask: Task<Void, Never>?
    var nettopReader: NettopReader?
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
            sleepAssertionRefreshTask?.cancel()
            launchItemRefreshTask?.cancel()
            stopProcessNetworkWatch()
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
        select(pid: accepted)
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

    /// Energy-card tap. A pid outside the table clears the selection.
    func selectSleepAssertion(pid: Int32) {
        updateCore { $0.selectSleepAssertion(pid: pid) }
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
        updateCore { core in
            core.noteMachineLabel(MachineInfo.toolbarLabel())
            return core.publishMemoryPageSort()
        }
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
        recordGateRetrying()
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
        await sampler.setReadsGPUShare(readsGPUShare)
        let result = await sampler.sample(readChipTemperature: selectedPage == .machine)
        if Task.isCancelled {
            samplingGate.invalidate()
            recordGateRetrying()
            return
        }
        let accepted = samplingGate.accept(flight)
        recordGateRetrying()
        applySample(result, accepted: accepted)
    }

    /// Every accepted frame, list failure, sampling failure, and stale flight
    /// reaches one presence observation. Model writes stay on the accepted paths.
    private func applySample(_ result: Result<SampledFrame, HostMemoryError>, accepted: Bool) {
        var next = core
        let effects = next.apply(
            result: result,
            accepted: accepted,
            page: next.selectedPage
        )
        if accepted {
            next.noteWindowedPids(WindowedAppLookup.pids(in: next.rows))
        }
        core = next
        perform(effects)
    }

    private func changePage(_ mutate: (inout DashboardCore) -> [DashboardEffect]) {
        updateCore(mutate)
    }

    func mutateCore(_ mutate: (inout DashboardCore) -> [DashboardEffect]) {
        updateCore(mutate)
    }

    func runCore(_ mutate: (inout DashboardCore) -> [DashboardEffect]) async {
        var next = core
        let effects = mutate(&next)
        core = next
        await performExternal(effects)
    }

    /// Writes the gate bit onto `core`. The gate remains the only retry decision.
    private func recordGateRetrying() {
        var next = core
        next.noteRetrying(samplingGate.retrying)
        core = next
    }

    private func updateCore(_ mutate: (inout DashboardCore) -> [DashboardEffect]) {
        var next = core
        let effects = mutate(&next)
        core = next
        perform(effects)
    }

    private func performExternal(_ effects: [DashboardEffect]) async {
        for effect in effects {
            switch effect {
            case .terminate(let pid, let force, let token):
                let result = force
                    ? await ProcessActions.forceTerminate(pid: pid)
                    : await ProcessActions.terminate(pid: pid)
                if let token {
                    var next = core
                    next.finishQuit(
                        pid: pid,
                        token: token,
                        result: result,
                        taskCancelled: Task.isCancelled
                    )
                    core = next
                }
            case .confirmForceQuit(let displayName, let generation):
                let confirmed = ProcessActions.confirmForceQuit(displayName: displayName)
                var next = core
                let follow = next.resolveForceQuit(generation: generation, confirmed: confirmed)
                core = next
                await performExternal(follow)
            case .confirmResumeBeforeQuit(let pid, let displayName):
                let confirmed = ProcessActions.confirmResumeBeforeQuit(displayName: displayName)
                var next = core
                let follow = next.resolveResumeBeforeQuit(pid: pid, confirmed: confirmed)
                core = next
                await performExternal(follow)
            default:
                perform([effect])
            }
        }
    }

    private func perform(_ effects: [DashboardEffect]) {
        for effect in effects {
            switch effect {
            case .requestRetryWake:
                samplingGate.requestManualRetry()
                recordGateRetrying()
                sleepTask?.cancel()
            case .applyRisingAndWindowedSelection:
                updateCore { core in
                    core.applyRisingOnlySelection() + core.applyWindowedOnlySelection()
                }
            case .forwardSelectedPid(let pid):
                Task { await sampler.setSelectedPid(pid) }
            case .forwardMemoryPageSort(let sort):
                Task { await sampler.setMemoryPageSort(sort) }
            case .terminate, .confirmForceQuit, .confirmResumeBeforeQuit:
                break
            case .pauseProcess(let pid):
                ProcessPause.stop(pid)
                ProcessPause.store(core.pausedLedger)
            case .resumeProcess(let pid):
                ProcessPause.resume(pid)
                ProcessPause.store(core.pausedLedger)
            case .lowerPriority(let pid):
                let succeeded = ProcessPriority.lower(pid)
                var next = core
                next.finishLowerPriority(pid: pid, succeeded: succeeded)
                core = next
            case .restorePriority(let pid):
                ProcessPriority.restore(pid)
            case .setGPUSampling:
                break
            case .startMachineWatch, .stopMachineWatch:
                syncMachineWatch()
            case .startEnergyBatteryWatch, .stopEnergyBatteryWatch:
                syncEnergyBatteryWatch()
            case .startSleepAssertionWatch, .stopSleepAssertionWatch:
                syncSleepAssertionWatch()
            case .startLaunchItemWatch, .stopLaunchItemWatch:
                syncLaunchItemWatch()
            case .startProcessNetworkWatch, .stopProcessNetworkWatch:
                syncProcessNetworkWatch()
            case .lookupPublicIP(let queriedAt):
                let transport = PublicIPURLSessionTransport()
                Task { [weak self] in
                    let result = await PublicIPLookup.lookup(using: transport)
                    guard let self else { return }
                    let address: String?
                    if case .success(let found) = result {
                        address = found
                    } else {
                        address = nil
                    }
                    self.updateCore { $0.finishPublicIPLookup(address: address, queriedAt: queriedAt) }
                }
            case .requestLocationAuthorization:
                HostWiFiLocation.request()
            }
        }
    }
    var selectedEnergyExitedOnly: Bool { core.selectedEnergyExitedOnly }
}
