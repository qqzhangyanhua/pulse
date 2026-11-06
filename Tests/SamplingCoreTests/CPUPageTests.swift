import XCTest
@testable import SamplingCore

final class CPUPageTests: XCTestCase {
    func testOverviewLineUsesEmDashWhenSystemCPUIsMissing() {
        XCTAssertEqual(CPUPageCopy.overviewLine(systemCpuPercent: nil), "CPU · —")
        XCTAssertEqual(CPUPercentText.string(nil), "—")
        XCTAssertFalse(CPUPageCopy.overviewLine(systemCpuPercent: nil).contains("0"))
    }

    func testOverviewLineFormatsARealReadingAndKeepsRealZero() {
        XCTAssertEqual(CPUPageCopy.overviewLine(systemCpuPercent: 12.5), "CPU · 12.5%")
        XCTAssertEqual(CPUPageCopy.overviewLine(systemCpuPercent: 0), "CPU · 0.0%")
        XCTAssertEqual(CPUPercentText.string(200), "200.0%")
        XCTAssertNotEqual(CPUPercentText.string(nil), CPUPercentText.string(0))
    }

    func testBusiestCoreLineKeepsMissingAndRealZeroApart() {
        XCTAssertEqual(CPUPageCopy.busiestCoreLine(percent: nil), "最忙的一核 · —")
        XCTAssertFalse(CPUPageCopy.busiestCoreLine(percent: nil).contains("0"))
        XCTAssertEqual(CPUPageCopy.busiestCoreLine(percent: 0), "最忙的一核 · 0.0%")
        XCTAssertEqual(CPUPageCopy.busiestCoreLine(percent: 12.5), "最忙的一核 · 12.5%")
        XCTAssertNotEqual(
            CPUPageCopy.busiestCoreLine(percent: nil),
            CPUPageCopy.busiestCoreLine(percent: 0)
        )
    }

    func testBusiestCoreLineIsReadyOnlyAndDoesNotFeedCPUHistory() throws {
        let sentence = "最忙的一核 · "
        let model = try repoText("Pulse/Models/CPUPage.swift")
        XCTAssertEqual(occurrenceCount(of: sentence, in: model), 1)

        let view = try repoText("Pulse/Views/CPUOverviewSection.swift")
        XCTAssertFalse(view.contains(sentence))
        XCTAssertEqual(occurrenceCount(of: "CPUPageCopy.busiestCoreLine(percent: vm.busiestCorePercent)", in: view), 2)
        let sampling = try slice(from: "private var samplingBody", until: "private var failureBody", in: view)
        let failure = try slice(from: "private var failureBody", until: "private var readyBody", in: view)
        let ready = try slice(from: "private var readyBody", until: "private var readyAccessibilityLabel", in: view)
        XCTAssertFalse(sampling.contains("busiestCoreLine"))
        XCTAssertFalse(failure.contains("busiestCoreLine"))
        XCTAssertTrue(ready.contains("CPUPageCopy.busiestCoreLine(percent: vm.busiestCorePercent)"))
        XCTAssertTrue(view.contains("let core = CPUPageCopy.busiestCoreLine(percent: vm.busiestCorePercent)"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(vm.contains("busiestCorePercent = frame.busiestCorePercent"))
        XCTAssertTrue(vm.contains("nextCPU.record(percent: frame.systemCpuPercent, at: frame.snapshot.capturedAt)"))
        XCTAssertFalse(vm.contains("record(percent: frame.busiestCorePercent"))
        XCTAssertFalse(vm.contains("record(percent: vm.busiestCorePercent"))
        XCTAssertFalse(vm.contains("cpuHistory.record"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(sampler.contains("HostCPUReader.readCores()"))
        XCTAssertTrue(sampler.contains("BusiestCoreLoad.advance"))
        XCTAssertFalse(sampler.contains("cpuHistory"))
    }

    func testStatusCopyMatchesTheCPUPage() {
        XCTAssertEqual(CPUPageCopy.sampling, "正在采样…")
        XCTAssertEqual(CPUPageCopy.emptyTitle, "还没有进程数据")
        XCTAssertEqual(CPUPageCopy.failureTitle, "暂时读不到 CPU 数据")
        XCTAssertEqual(CPUPageCopy.retry, "重试")
        XCTAssertEqual(CPUPageCopy.failureMessage, "这轮采样没有回来，点重试再试。")
        XCTAssertEqual(CPUPageCopy.sidebarEmpty, "选一个进程看详情")
    }

    func testCPUCopyStaysCalm() {
        let blob = [
            CPUPageCopy.sampling,
            CPUPageCopy.emptyTitle,
            CPUPageCopy.emptyMessage,
            CPUPageCopy.failureTitle,
            CPUPageCopy.failureMessage,
            CPUPageCopy.retry,
            CPUPageCopy.sidebarEmpty,
            CPUPageCopy.filteredEmptyTitle,
            CPUPageCopy.filteredEmptyMessage,
            CPUPageCopy.filteredEmptyButton,
            CPUPageCopy.overviewLine(systemCpuPercent: nil),
            CPUPageCopy.overviewLine(systemCpuPercent: 90),
        ].joined(separator: "\n")
        for word in ["危险", "泄漏", "泄露", "告警", "崩溃"] {
            XCTAssertFalse(blob.contains(word), word)
        }
    }

    func testPhaseResolverDistinguishesLoadingEmptyAndFailure() {
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .sampling,
                processCount: 0,
                visibleCount: 0,
                hasActiveFilter: false,
                processListFailed: false
            ),
            .sampling
        )
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .failed,
                processCount: 0,
                visibleCount: 0,
                hasActiveFilter: false,
                processListFailed: false
            ),
            .failed
        )
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .ready,
                processCount: 0,
                visibleCount: 0,
                hasActiveFilter: false,
                processListFailed: true
            ),
            .failed
        )
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .ready,
                processCount: 0,
                visibleCount: 0,
                hasActiveFilter: false,
                processListFailed: false
            ),
            .empty
        )
    }

    func testReadyFrameWithNilSystemCPUIsNotAFailure() {
        XCTAssertEqual(CPUPageCopy.overviewLine(systemCpuPercent: nil), "CPU · —")
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .ready,
                processCount: 2,
                visibleCount: 2,
                hasActiveFilter: false,
                processListFailed: false
            ),
            .ready
        )
    }

    func testNameFilterMatchesMemoryPageAndSortsCPUDescending() {
        let rows = [
            process(pid: 1, name: "Zero", cpu: 0, memory: 10),
            process(pid: 2, name: "Missing", cpu: nil, memory: 90),
            process(pid: 3, name: "Busy App", cpu: 40, memory: 20),
            process(pid: 4, name: "idle helper", cpu: 5, memory: 30),
        ]

        let filtered = ProcessNameFilter.apply(rows, query: "  app ")
        XCTAssertEqual(filtered.map(\.pid), [3])
        XCTAssertEqual(ProcessNameFilter.apply(rows, query: "   ").map(\.pid), rows.map(\.pid))

        let cpuOrder = ProcessTableSort.defaultSort(for: .cpu).ordered(rows)
        XCTAssertEqual(cpuOrder.map(\.name), ["Busy App", "idle helper", "Zero", "Missing"])

        let memoryOrder = ProcessTableSort.defaultSort(for: .memory).ordered(rows)
        XCTAssertEqual(memoryOrder.map(\.name), ["Missing", "idle helper", "Busy App", "Zero"])
    }

    func testNilCPUSortsBelowARealZero() {
        let rows = [
            process(pid: 1, name: "missing", cpu: nil, memory: 1),
            process(pid: 2, name: "idle", cpu: 0, memory: 1),
        ]
        let ordered = ProcessTableSort.defaultSort(for: .cpu).ordered(rows)
        XCTAssertEqual(ordered.map(\.name), ["idle", "missing"])
        XCTAssertEqual(rows[0].cpuSortKey, -1)
    }

    func testCPUPageKeepsNameCPUAndMemoryColumns() {
        XCTAssertEqual(ProcessColumnTitle.cpuPage, ["名称", "CPU", "内存", "线程"])
        XCTAssertTrue(ProcessColumnTitle.cpuPage.contains(ProcessColumnTitle.memory))
    }

    func testMemoryCPUAndNetworkTabsAreSelectable() {
        XCTAssertTrue(DashboardPage.memory.isSelectable)
        XCTAssertTrue(DashboardPage.cpu.isSelectable)
        XCTAssertTrue(DashboardPage.network.isSelectable)
        XCTAssertTrue(DashboardPage.disk.isSelectable)
        XCTAssertFalse(DashboardPage.gpu.isSelectable)
    }

    func testColdStartStaysOnMemoryAndCPUSelectionChangesTheDefaultSort() {
        var navigation = DashboardNavigation()
        XCTAssertEqual(navigation.selectedPage, .memory)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))

        navigation.select(.cpu)
        XCTAssertEqual(navigation.selectedPage, .cpu)
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .cpu, descending: true))

        navigation.updateSort(ProcessTableSort(column: .name, descending: false))
        navigation.select(.gpu)
        XCTAssertEqual(navigation.selectedPage, .cpu)
        XCTAssertEqual(navigation.sort.column, .name)

        navigation.select(.cpu)
        XCTAssertEqual(navigation.sort.column, .name, "Re-selecting the open page keeps the user's sort")

        navigation.select(.memory)
        XCTAssertEqual(navigation.selectedPage, .memory)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))
    }

    func testMenuBarFocusStillForcesMemoryWithoutResettingAnAlreadyMemorySort() {
        var navigation = DashboardNavigation()
        navigation.select(.cpu)
        navigation.focusMemoryPage()
        XCTAssertEqual(navigation.selectedPage, .memory)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))

        navigation.updateSort(ProcessTableSort(column: .name, descending: false))
        navigation.focusMemoryPage()
        XCTAssertEqual(navigation.selectedPage, .memory)
        XCTAssertEqual(navigation.sort.column, .name)
    }

    func testSystemCPUHistorySkipsNilAndDoesNotPlotZero() {
        var history = SystemCPUHistory(limit: 3)
        let first = Date(timeIntervalSince1970: 1)
        history.record(percent: nil, at: first)
        XCTAssertTrue(history.samples.isEmpty)

        history.record(percent: 10, at: first)
        history.record(percent: nil, at: Date(timeIntervalSince1970: 2))
        history.record(percent: 10, at: first)
        XCTAssertEqual(history.samples.map(\.value), [10])

        history.record(percent: 0, at: Date(timeIntervalSince1970: 3))
        history.record(percent: 20, at: Date(timeIntervalSince1970: 4))
        history.record(percent: 30, at: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(history.samples.map(\.value), [0, 20, 30])

        history.reset()
        XCTAssertTrue(history.samples.isEmpty)
    }

    func testResourceFilterEmptyPhaseAndLegacyCopyStay() {
        XCTAssertEqual(CPUPageCopy.sampling, "正在采样…")
        XCTAssertEqual(CPUPageCopy.emptyTitle, "还没有进程数据")
        XCTAssertEqual(CPUPageCopy.emptyMessage, "这一帧没有进程可显示。")
        XCTAssertEqual(CPUPageCopy.failureTitle, "暂时读不到 CPU 数据")
        XCTAssertEqual(CPUPageCopy.failureMessage, "这轮采样没有回来，点重试再试。")
        XCTAssertEqual(CPUPageCopy.retry, "重试")
        XCTAssertEqual(CPUPageCopy.sidebarEmpty, "选一个进程看详情")
        XCTAssertEqual(CPUPageCopy.filteredEmptyTitle, "没有匹配的 App")
        XCTAssertEqual(CPUPageCopy.filteredEmptyMessage, "换个名称试试，或清空过滤。")
        XCTAssertEqual(CPUPageCopy.filteredEmptyButton, "清空过滤")
        XCTAssertNotEqual(CPUPageCopy.filteredEmptyMessage, "清空名称和仅上涨过滤。")

        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .ready,
                processCount: 4,
                visibleCount: 0,
                hasActiveFilter: true,
                processListFailed: false
            ),
            .filteredEmpty
        )
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .sampling,
                processCount: 0,
                visibleCount: 0,
                hasActiveFilter: true,
                processListFailed: false
            ),
            .sampling
        )
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .failed,
                processCount: 0,
                visibleCount: 0,
                hasActiveFilter: true,
                processListFailed: false
            ),
            .failed
        )
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .ready,
                processCount: 0,
                visibleCount: 0,
                hasActiveFilter: true,
                processListFailed: true
            ),
            .failed
        )
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .ready,
                processCount: 0,
                visibleCount: 0,
                hasActiveFilter: false,
                processListFailed: false
            ),
            .empty
        )
        XCTAssertEqual(
            CPUPagePhaseResolver.resolve(
                loadState: .ready,
                processCount: 4,
                visibleCount: 1,
                hasActiveFilter: true,
                processListFailed: false
            ),
            .ready
        )
    }

    func testColumnClickTogglesAndMetricColumnsStartDescending() {
        let memory = ProcessTableSort.defaultSort(for: .memory)
        let cpu = memory.selecting(.cpu)
        XCTAssertEqual(cpu, ProcessTableSort(column: .cpu, descending: true))
        XCTAssertEqual(cpu.selecting(.cpu), ProcessTableSort(column: .cpu, descending: false))
        XCTAssertEqual(cpu.selecting(.name), ProcessTableSort(column: .name, descending: false))
    }

    private func process(pid: Int32, name: String, cpu: Double?, memory: UInt64) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: cpu,
            memoryBytes: memory,
            threadCount: 1
        )
    }

    private func repoText(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func slice(from start: String, until end: String, in source: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
        else {
            XCTFail("missing slice \(start)")
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}
