import XCTest
@testable import SamplingCore

final class NetworkPageTests: XCTestCase {
    func testOverviewLineUsesEmDashWhenHostRatesAreMissing() {
        XCTAssertEqual(NetworkPageCopy.overviewLine(rates: .missing), "下行 · — · 上行 · —")
        XCTAssertEqual(NetworkRateText.string(nil), "—")
        XCTAssertFalse(NetworkPageCopy.overviewLine(rates: .missing).contains("0"))
        XCTAssertNotEqual(NetworkRateText.string(nil), NetworkRateText.string(0))
    }

    func testOverviewLineFormatsARealReadingAndKeepsRealZero() {
        let rates = HostNetworkRates(inboundBytesPerSecond: 12.5 * 1_048_576, outboundBytesPerSecond: 0)
        XCTAssertEqual(NetworkPageCopy.overviewLine(rates: rates), "下行 · 12.5 MB/秒 · 上行 · 0 字节/秒")
        XCTAssertEqual(NetworkRateText.string(0), "0 字节/秒")
        XCTAssertEqual(NetworkRateText.string(1_024), "1 KB/秒")
        XCTAssertEqual(NetworkRateText.string(2 * 1_073_741_824), "2 GB/秒")
        XCTAssertNotEqual(NetworkRateText.string(nil), "0 字节/秒")
        XCTAssertNotEqual(NetworkRateText.string(nil), "0 B/s")
    }

    func testCardTitlesAreUplinkAndDownlink() {
        XCTAssertEqual(NetworkPageCopy.inboundTitle, "下行")
        XCTAssertEqual(NetworkPageCopy.outboundTitle, "上行")
        XCTAssertEqual(NetworkPageCopy.columnTitle, "网络")
    }

    func testStatusCopyMatchesTheNetworkPage() {
        XCTAssertEqual(NetworkPageCopy.sampling, "正在采样…")
        XCTAssertEqual(NetworkPageCopy.emptyTitle, "还没有进程数据")
        XCTAssertEqual(NetworkPageCopy.emptyMessage, "这一帧没有进程可显示。")
        XCTAssertEqual(NetworkPageCopy.failureTitle, "暂时读不到网络数据")
        XCTAssertEqual(NetworkPageCopy.failureMessage, "这轮采样没有回来，点重试再试。")
        XCTAssertEqual(NetworkPageCopy.retry, "重试")
        XCTAssertEqual(NetworkPageCopy.sidebarEmpty, "选一个进程看详情")
        XCTAssertEqual(NetworkPageCopy.processNetworkUnavailable, "暂不可用")
        XCTAssertEqual(NetworkPageCopy.processRateHelp, "没有进程速率。主机下行和上行在总览。")
    }

    func testProcessRateHelpIsOneConstantAndTwoHelpModifiers() throws {
        let sentence = "没有进程速率。主机下行和上行在总览。"
        XCTAssertEqual(NetworkPageCopy.processRateHelp, sentence)
        let model = try repoText("Pulse/Models/NetworkPage.swift")
        XCTAssertEqual(occurrenceCount(of: sentence, in: model), 1)

        let call = ".help(NetworkPageCopy.processRateHelp)"
        let table = try repoText("Pulse/Views/ProcessTablePane.swift")
        let sidebar = try repoText("Pulse/Views/ProcessDetailSidebar.swift")
        XCTAssertEqual(occurrenceCount(of: call, in: table), 1)
        XCTAssertEqual(occurrenceCount(of: call, in: sidebar), 1)
        XCTAssertFalse(table.contains(sentence))
        XCTAssertFalse(sidebar.contains(sentence))
        XCTAssertTrue(table.contains("Text(row.networkAvailability.label)"))
        XCTAssertTrue(table.contains("\"网络 \\(row.networkAvailability.label)\""))
        XCTAssertFalse(table.contains("网络 \\(row.networkAvailability.label)。\(NetworkPageCopy.processRateHelp)"))
        XCTAssertTrue(table.contains("staticHeader(ProcessColumnTitle.network)"))
        XCTAssertFalse(table.contains("sortHeader(ProcessColumnTitle.network"))
        XCTAssertTrue(sidebar.contains("Text(ResourceDetailPageProjection.processNetworkUnavailable)"))

        let projection = try repoText("Pulse/Models/ResourceDetailPageProjection.swift")
        XCTAssertFalse(projection.contains(sentence))
        XCTAssertTrue(projection.contains("static let processNetworkUnavailable = \"当前进程网络暂不可用\""))
    }

    func testNetworkCopyStaysCalm() {
        let blob = [
            NetworkPageCopy.sampling,
            NetworkPageCopy.emptyTitle,
            NetworkPageCopy.emptyMessage,
            NetworkPageCopy.failureTitle,
            NetworkPageCopy.failureMessage,
            NetworkPageCopy.retry,
            NetworkPageCopy.sidebarEmpty,
            NetworkPageCopy.processNetworkUnavailable,
            NetworkPageCopy.inboundTitle,
            NetworkPageCopy.outboundTitle,
            NetworkPageCopy.overviewLine(rates: .missing),
            NetworkPageCopy.overviewLine(
                rates: HostNetworkRates(inboundBytesPerSecond: 90, outboundBytesPerSecond: 40)
            ),
        ].joined(separator: "\n")
        for word in ["危险", "泄漏", "泄露", "超速", "告警", "被盗", "中招", "异常流量", "完全磁盘访问", "未授权"] {
            XCTAssertFalse(blob.contains(word), word)
        }
    }

    func testProcessNetworkColumnIsUnavailableNotAFakeRate() {
        let row = ProcessRow(
            pid: 11,
            name: "helper",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 4,
            memoryBytes: 8,
            threadCount: 2
        )
        XCTAssertEqual(row.networkAvailability, .unavailable)
        XCTAssertEqual(row.networkAvailability.label, NetworkPageCopy.processNetworkUnavailable)
        XCTAssertEqual(ProcessColumnTitle.network, "网络")
        XCTAssertEqual(ProcessColumnTitle.networkPage, ["名称", "CPU", "内存", "网络", "线程"])
        XCTAssertNotEqual(row.networkAvailability.label, "—")
        XCTAssertNotEqual(row.networkAvailability.label, "0")
        XCTAssertNotEqual(row.networkAvailability.label, "0 字节/秒")
    }

    func testNetworkAndGPUTabsAreSelectable() {
        XCTAssertTrue(DashboardPage.memory.isSelectable)
        XCTAssertTrue(DashboardPage.cpu.isSelectable)
        XCTAssertTrue(DashboardPage.network.isSelectable)
        XCTAssertTrue(DashboardPage.disk.isSelectable)
        XCTAssertTrue(DashboardPage.machine.isSelectable)
        XCTAssertTrue(DashboardPage.gpu.isSelectable)
    }

    func testColdStartStaysOnMemoryAndNetworkDefaultsToCPUSort() {
        var navigation = DashboardNavigation()
        XCTAssertEqual(navigation.selectedPage, .memory)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))

        navigation.select(.network)
        XCTAssertEqual(navigation.selectedPage, .network)
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .cpu, descending: true))
        XCTAssertNotEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))

        navigation.updateSort(ProcessTableSort(column: .name, descending: false))
        navigation.select(.network)
        XCTAssertEqual(navigation.sort.column, .name, "Re-selecting the open page keeps the user's sort")

        navigation.select(.gpu)
        XCTAssertEqual(navigation.selectedPage, .gpu)
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .memory, descending: true))

        navigation.select(.cpu)
        XCTAssertEqual(navigation.selectedPage, .cpu)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .cpu))
    }

    func testNetworkPageSortsByCPUDescendingAndNilsSink() {
        let rows = [
            process(pid: 1, name: "Zero", cpu: 0, memory: 10),
            process(pid: 2, name: "Missing", cpu: nil, memory: 90),
            process(pid: 3, name: "Busy App", cpu: 40, memory: 20),
            process(pid: 4, name: "idle helper", cpu: 5, memory: 30),
        ]

        let ordered = ProcessTableSort.defaultSort(for: .network).ordered(rows)
        XCTAssertEqual(ordered.map(\.name), ["Busy App", "idle helper", "Zero", "Missing"])
        XCTAssertEqual(ProcessTableSort.defaultSort(for: .network).column, .cpu)
        XCTAssertTrue(ProcessTableSort.defaultSort(for: .network).descending)
    }

    func testReadyFrameWithNilHostRatesIsNotAFailure() {
        XCTAssertEqual(NetworkPageCopy.overviewLine(rates: .missing), "下行 · — · 上行 · —")
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

    func testSystemNetworkHistorySkipsNilAndDoesNotPlotFakeZero() {
        var history = SystemNetworkHistory(limit: 3)
        let first = Date(timeIntervalSince1970: 1)
        history.record(rates: .missing, at: first)
        XCTAssertTrue(history.inbound.samples.isEmpty)
        XCTAssertTrue(history.outbound.samples.isEmpty)

        history.record(
            rates: HostNetworkRates(inboundBytesPerSecond: 10, outboundBytesPerSecond: nil),
            at: first
        )
        history.record(rates: .missing, at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(history.inbound.samples.map(\.value), [10])
        XCTAssertTrue(history.outbound.samples.isEmpty)

        history.record(
            rates: HostNetworkRates(inboundBytesPerSecond: 0, outboundBytesPerSecond: 20),
            at: Date(timeIntervalSince1970: 3)
        )
        history.record(
            rates: HostNetworkRates(inboundBytesPerSecond: 30, outboundBytesPerSecond: 40),
            at: Date(timeIntervalSince1970: 4)
        )
        history.record(
            rates: HostNetworkRates(inboundBytesPerSecond: 50, outboundBytesPerSecond: 60),
            at: Date(timeIntervalSince1970: 5)
        )
        XCTAssertEqual(history.inbound.samples.map(\.value), [0, 30, 50])
        XCTAssertEqual(history.outbound.samples.map(\.value), [20, 40, 60])

        history.reset()
        XCTAssertTrue(history.inbound.samples.isEmpty)
        XCTAssertTrue(history.outbound.samples.isEmpty)
    }

    func testMenuBarFocusStillForcesMemoryFromTheNetworkPage() {
        var navigation = DashboardNavigation()
        navigation.select(.network)
        navigation.focusMemoryPage()
        XCTAssertEqual(navigation.selectedPage, .memory)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))
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
}
