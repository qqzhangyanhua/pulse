import Combine
import Foundation

@MainActor
final class MemoryDashboardVM: ObservableObject {
    @Published private(set) var loadState: LoadState = .sampling
    @Published private(set) var snapshot: MemorySnapshot?
    @Published private(set) var systemCpuPercent: Double?
    @Published private(set) var hostNetworkRates = HostNetworkRates.missing
    @Published private(set) var hostDiskRates = HostDiskRates.missing
    @Published private(set) var rows: [ProcessRow] = []
    @Published private(set) var processListFailed = false
    @Published private(set) var detail: ProcessDetail?
    /// Bounded Top N=5 memory series. List rows look up `memoryGrowthListBadge(for:)`.
    @Published private(set) var topMemorySeries: [Int32: [ChartSample]] = [:]
    @Published private(set) var machineLabel: String?
    /// The only session quit store. Phase and message are projections of this.
    @Published var quitOutcome = ProcessQuitOutcome()
    @Published var sidebarSubjectPid: Int32?
    var quitPhase: QuitPhase { sidebar.quitPhase }
    var quitMessage: String? { sidebar.quitMessage }
    @Published private(set) var samplingFailed = false
    /// Gate projection. Not a second retry flag.
    @Published private(set) var isRetrying = false
    @Published private(set) var usageHistory = UsageHistory()
    @Published private(set) var cpuHistory = SystemCPUHistory()
    @Published private(set) var networkHistory = SystemNetworkHistory()
    @Published private(set) var diskHistory = SystemDiskHistory()
    @Published var filter = ""
    /// Memory-tab only. Default OFF. Session-scoped; not a Sampler or preference write.
    @Published var risingOnlyFilter = false {
        didSet {
            guard oldValue != risingOnlyFilter else { return }
            applyRisingOnlySelection()
        }
    }
    /// One-shot memory Top card reveal. The next locate replaces it.
    @Published var topAppLocateReveal: TopAppLocation.Reveal?
    @Published private(set) var navigation = DashboardNavigation()
    /// Last memory-page sort, readable on the MainActor. Not a second published sort field.
    private var publication = MemoryPageSortPublication()

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

    var visibleRows: [ProcessRow] {
        MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: filter,
            page: selectedPage,
            risingOnly: risingOnlyFilter,
            seriesByPid: topMemorySeries
        )
    }

    /// Visible rows in the current table sort. Not stored and not published.
    var sortedRows: [ProcessRow] {
        tableSort.ordered(visibleRows)
    }

    /// Strip B. Unfiltered `rows` ordered by the published memory-page sort.
    /// Does not read the name query, rising-only keep, or a resource-tab live `tableSort`.
    var menuBarPopover: MenuBarPopoverSnapshot {
        MenuBarPopoverSnapshot.project(
            pressure: snapshot?.pressure,
            usedBytes: snapshot?.usedBytes,
            samplingFailed: samplingFailed,
            rows: rows,
            processListFailed: processListFailed,
            sort: publication.sort
        )
    }

    var selectedRow: ProcessRow? {
        guard let selectedPid else { return nil }
        return rows.first { $0.pid == selectedPid }
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
        var next = navigation
        next.focusMemoryPage()
        navigation = next
        publishMemoryPageSort()
        applyRisingOnlySelection()
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

    /// Memory, CPU, network, and disk. GPU stays on the current page.
    func selectPage(_ page: DashboardPage) {
        var next = navigation
        next.select(page)
        navigation = next
        publishMemoryPageSort()
        applyRisingOnlySelection()
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

    private func nanosecondsElapsed(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> UInt64 {
        let duration = start.duration(to: end)
        let seconds = duration.components.seconds
        let attoseconds = duration.components.attoseconds
        if seconds < 0 { return 0 }
        let secNanos = UInt64(seconds) &* 1_000_000_000
        let nanoPart = attoseconds <= 0 ? 0 : UInt64(attoseconds / 1_000_000_000)
        return secNanos &+ nanoPart
    }

    private func tick(_ flight: SamplingFlight) async {
        let result = await sampler.sample()
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
                    rows = frame.rows
                    processListFailed = frame.processListFailed
                    topMemorySeries = frame.topMemorySeries
                    loadState = applied.loadState
                    observation = ProcessQuitSession.Observation(
                        rows: frame.rows,
                        liveDetail: frame.detail,
                        detailToFreeze: detail,
                        processListFailed: frame.processListFailed,
                        samplingFailed: false,
                        freshnessInsufficient: false
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
        if selectedPid != effect.listSelectedPid {
            selectedPid = effect.listSelectedPid
        }
        if sidebarSubjectPid != effect.sidebarSubjectPid {
            sidebarSubjectPid = effect.sidebarSubjectPid
        }
        if detail != effect.liveDetail {
            detail = effect.liveDetail
        }
        if applyRisingOnly {
            applyRisingOnlySelection()
        }
    }
}
