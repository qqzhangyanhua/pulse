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
    @Published private(set) var quitPhase: QuitPhase = .idle
    @Published private(set) var quitMessage: String?
    @Published private(set) var samplingFailed = false
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
    @Published private(set) var navigation = DashboardNavigation()

    @Published var selectedPid: Int32? {
        didSet {
            guard oldValue != selectedPid else { return }
            detail = nil
            quitPhase = .idle
            quitMessage = nil
            let pid = selectedPid
            Task { await sampler.setSelectedPid(pid) }
        }
    }

    private let sampler = MemorySampler()
    private var loopTask: Task<Void, Never>?
    private var started = false
    private var samplingSession = SamplingSession()
    private var samplingClock = SamplingClock()

    var visibleRows: [ProcessRow] {
        MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: filter,
            page: selectedPage,
            risingOnly: risingOnlyFilter,
            seriesByPid: topMemorySeries
        )
    }

    /// Strip B. Full memory-ordered `rows`, never the filtered table or its header sort.
    var menuBarPopover: MenuBarPopoverSnapshot {
        MenuBarPopoverSnapshot.project(
            pressure: snapshot?.pressure,
            usedBytes: snapshot?.usedBytes,
            samplingFailed: samplingFailed,
            rows: rows,
            processListFailed: processListFailed
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

    /// Memory-page sidebar trend. Reads the current detail series, so a pid or detail clear
    /// drops the previous process's rising line on the same turn.
    var memoryGrowthSlot: MemoryGrowthSlot? {
        MemoryGrowthSidebar.slot(
            page: selectedPage,
            selectedPid: selectedPid,
            detailSeries: detail?.memorySeries
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
                let plan = self.samplingClock.plan(step: self.samplingSession.step)
                if plan.sample {
                    await self.tick()
                }
                try? await Task.sleep(nanoseconds: plan.sleepNanoseconds)
                self.samplingClock.recordSleep(plan.sleepNanoseconds)
            }
        }
    }

    /// App hook for scene phase. Background keeps the same sampler and only lengthens the interval.
    func setForeground(_ active: Bool) {
        samplingSession.setForeground(active)
    }

    func retrySampling() {
        loadState = .sampling
        snapshot = nil
        systemCpuPercent = nil
        hostNetworkRates = .missing
        hostDiskRates = .missing
        rows = []
        processListFailed = false
        samplingFailed = false
        var clearedUsage = usageHistory
        clearedUsage.record(nil)
        usageHistory = clearedUsage
        var clearedCPU = cpuHistory
        clearedCPU.reset()
        cpuHistory = clearedCPU
        var clearedNetwork = networkHistory
        clearedNetwork.reset()
        networkHistory = clearedNetwork
        var clearedDisk = diskHistory
        clearedDisk.reset()
        diskHistory = clearedDisk
        Task { await tick() }
    }

    func quitSelected() async {
        guard let pid = selectedPid else { return }
        quitPhase = .quitting
        quitMessage = nil
        let result = await ProcessActions.terminate(pid: pid)
        applyQuit(result, fallback: "未能退出。可以请系统立即结束该进程。")
    }

    func forceQuitSelected() async {
        guard let pid = selectedPid, let name = selectedRow?.name ?? detail?.row.name else { return }
        guard ProcessActions.confirmForceQuit(displayName: name) else { return }
        quitPhase = .quitting
        quitMessage = nil
        let result = await ProcessActions.forceTerminate(pid: pid)
        applyQuit(result, fallback: "系统未能结束该进程。")
    }

    private func applyQuit(_ result: ProcessActionResult, fallback: String) {
        switch result {
        case .exited, .notFound:
            selectedPid = nil
            detail = nil
            quitPhase = .idle
            quitMessage = nil
        case .requestFailed, .stillRunning:
            quitPhase = .failed
            quitMessage = fallback
        }
    }

    /// Same-beat clear when the rising-only keep hides `selectedPid`. OFF does not restore.
    private func applyRisingOnlySelection() {
        let next = MemoryGrowthRisingFilter.selectedPid(
            current: selectedPid,
            rows: rows,
            nameQuery: filter,
            page: selectedPage,
            risingOnly: risingOnlyFilter,
            seriesByPid: topMemorySeries
        )
        guard next != selectedPid else { return }
        selectedPid = next
    }

    /// Only the memory-page sort drives Top 5. Other tabs keep the last memory sort.
    private func publishMemoryPageSort() {
        guard selectedPage == .memory else { return }
        let sort = tableSort
        Task { await sampler.setMemoryPageSort(sort) }
    }

    private func tick() async {
        let result = await sampler.sample()
        switch result {
        case .success(let frame):
            samplingFailed = false
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
            if let frameDetail = frame.detail {
                detail = frameDetail
            } else if let pid = selectedPid, !frame.rows.contains(where: { $0.pid == pid }) {
                selectedPid = nil
                detail = nil
                if quitPhase == .quitting {
                    quitPhase = .idle
                    quitMessage = nil
                }
            }
            applyRisingOnlySelection()
            loadState = .ready
        case .failure:
            samplingFailed = true
            if snapshot == nil {
                loadState = .failed
            }
        }
    }
}
