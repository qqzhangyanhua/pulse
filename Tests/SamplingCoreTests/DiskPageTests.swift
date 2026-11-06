import XCTest
@testable import SamplingCore

final class DiskPageTests: XCTestCase {
    func testOverviewLineUsesEmDashWhenHostRatesAreMissing() {
        XCTAssertEqual(DiskPageCopy.overviewLine(rates: .missing), "读取 · — · 写入 · —")
        XCTAssertEqual(DiskRateText.string(nil), "—")
        XCTAssertEqual(DiskPageCopy.processRates(read: nil, write: nil), "— · —")
        XCTAssertFalse(DiskPageCopy.overviewLine(rates: .missing).contains("0"))
        XCTAssertNotEqual(DiskRateText.string(nil), DiskRateText.string(0))
    }

    func testOverviewLineFormatsARealReadingAndKeepsRealZero() {
        let rates = HostDiskRates(readBytesPerSecond: 12.5 * 1_048_576, writeBytesPerSecond: 0)
        XCTAssertEqual(DiskPageCopy.overviewLine(rates: rates), "读取 · 12.5 MB/秒 · 写入 · 0 字节/秒")
        XCTAssertEqual(DiskRateText.string(0), "0 字节/秒")
        XCTAssertEqual(DiskRateText.string(1_024), "1 KB/秒")
        XCTAssertEqual(DiskRateText.string(2 * 1_073_741_824), "2 GB/秒")
        XCTAssertNotEqual(DiskRateText.string(nil), "0 字节/秒")
        XCTAssertNotEqual(DiskRateText.string(nil), "0 B/s")
    }

    func testCardTitlesAreReadAndWrite() {
        XCTAssertEqual(DiskPageCopy.readTitle, "读取")
        XCTAssertEqual(DiskPageCopy.writeTitle, "写入")
        XCTAssertEqual(ProcessColumnTitle.diskRead, "读取")
        XCTAssertEqual(ProcessColumnTitle.diskWrite, "写入")
    }

    func testStatusCopyMatchesTheDiskPage() {
        XCTAssertEqual(DiskPageCopy.sampling, "正在采样…")
        XCTAssertEqual(DiskPageCopy.emptyTitle, "暂无磁盘数据")
        XCTAssertEqual(DiskPageCopy.failureTitle, "暂时读不到磁盘数据，稍后重试")
        XCTAssertEqual(DiskPageCopy.retry, "重试")
        XCTAssertEqual(DiskPageCopy.failureMessage, "这轮采样没有回来，点重试再试。")
        XCTAssertEqual(DiskPageCopy.sidebarEmpty, "选一个进程看详情")
        XCTAssertEqual(DiskPageCopy.chartCollecting, "正在采样…")
    }

    func testDiskCopyStaysCalm() {
        let blob = [
            DiskPageCopy.sampling,
            DiskPageCopy.emptyTitle,
            DiskPageCopy.emptyMessage,
            DiskPageCopy.failureTitle,
            DiskPageCopy.failureMessage,
            DiskPageCopy.retry,
            DiskPageCopy.sidebarEmpty,
            DiskPageCopy.readTitle,
            DiskPageCopy.writeTitle,
            DiskPageCopy.overviewLine(rates: .missing),
            DiskPageCopy.overviewLine(
                rates: HostDiskRates(readBytesPerSecond: 90, writeBytesPerSecond: 40)
            ),
            DiskPageCopy.processRates(read: nil, write: nil),
        ].joined(separator: "\n")
        for word in [
            "危险", "泄漏", "泄露", "超速", "告警", "被盗", "中招",
            "狂写", "磁盘将满", "被占满", "异常 IO", "完全磁盘访问", "未授权", "磁盘告警",
        ] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.contains("暂不可用"))
    }

    func testProcessDiskColumnUsesEmDashNotUnavailableOrFakeZero() {
        let row = ProcessRow(
            pid: 11,
            name: "helper",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 4,
            memoryBytes: 8,
            threadCount: 2
        )
        XCTAssertNil(row.diskReadBytesPerSecond)
        XCTAssertNil(row.diskWriteBytesPerSecond)
        XCTAssertEqual(DiskPageCopy.processRates(read: row.diskReadBytesPerSecond, write: row.diskWriteBytesPerSecond), "— · —")
        XCTAssertNotEqual(DiskPageCopy.processRates(read: nil, write: nil), "暂不可用")
        XCTAssertNotEqual(DiskPageCopy.processRates(read: nil, write: nil), "0 字节/秒")
        XCTAssertEqual(ProcessColumnTitle.diskPage, ["名称", "CPU", "内存", "读取", "写入", "线程"])
        XCTAssertEqual(row.networkAvailability.label, "暂不可用")
    }

    func testDiskTabIsSelectableAndGPUStaysGray() {
        XCTAssertTrue(DashboardPage.memory.isSelectable)
        XCTAssertTrue(DashboardPage.cpu.isSelectable)
        XCTAssertTrue(DashboardPage.network.isSelectable)
        XCTAssertTrue(DashboardPage.disk.isSelectable)
        XCTAssertFalse(DashboardPage.gpu.isSelectable)
    }

    func testColdStartStaysOnMemoryAndDiskDefaultsToCombinedRateSort() {
        var navigation = DashboardNavigation()
        XCTAssertEqual(navigation.selectedPage, .memory)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))

        navigation.select(.disk)
        XCTAssertEqual(navigation.selectedPage, .disk)
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .disk, descending: true))
        XCTAssertNotEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))
        XCTAssertNotEqual(navigation.sort, ProcessTableSort.defaultSort(for: .cpu))

        navigation.updateSort(ProcessTableSort(column: .name, descending: false))
        navigation.select(.gpu)
        XCTAssertEqual(navigation.selectedPage, .disk)
        XCTAssertEqual(navigation.sort.column, .name)

        navigation.select(.disk)
        XCTAssertEqual(navigation.sort.column, .name, "Re-selecting the open page keeps the user's sort")

        navigation.select(.cpu)
        XCTAssertEqual(navigation.selectedPage, .cpu)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .cpu))
    }

    func testDiskPageSortsByCombinedRateDescendingAndNilsSink() {
        let rows = [
            process(pid: 1, name: "Zero", read: 0, write: 0, memory: 10),
            process(pid: 2, name: "Missing", read: nil, write: nil, memory: 90),
            process(pid: 3, name: "Busy App", read: 40, write: 10, memory: 20),
            process(pid: 4, name: "idle helper", read: 5, write: 0, memory: 30),
            process(pid: 5, name: "partial", read: 80, write: nil, memory: 40),
        ]

        let ordered = ProcessTableSort.defaultSort(for: .disk).ordered(rows)
        XCTAssertEqual(ordered.map(\.name), ["Busy App", "idle helper", "Zero", "Missing", "partial"])
        XCTAssertEqual(ProcessTableSort.defaultSort(for: .disk).column, .disk)
        XCTAssertTrue(ProcessTableSort.defaultSort(for: .disk).descending)
        XCTAssertEqual(rows[2].diskSortKey, 50)
        XCTAssertEqual(rows[0].diskSortKey, 0)
        XCTAssertEqual(rows[1].diskSortKey, -1)
        XCTAssertEqual(rows[4].diskSortKey, -1)
        XCTAssertLessThan(rows[1].diskSortKey, rows[0].diskSortKey)
    }

    func testReadyFrameWithNilHostRatesIsNotAFailure() {
        XCTAssertEqual(DiskPageCopy.overviewLine(rates: .missing), "读取 · — · 写入 · —")
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

    func testSystemDiskHistorySkipsNilAndDoesNotPlotFakeZero() {
        var history = SystemDiskHistory(limit: 3)
        let first = Date(timeIntervalSince1970: 1)
        history.record(rates: .missing, at: first)
        XCTAssertTrue(history.read.samples.isEmpty)
        XCTAssertTrue(history.write.samples.isEmpty)

        history.record(
            rates: HostDiskRates(readBytesPerSecond: 10, writeBytesPerSecond: nil),
            at: first
        )
        history.record(rates: .missing, at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(history.read.samples.map(\.value), [10])
        XCTAssertTrue(history.write.samples.isEmpty)

        history.record(
            rates: HostDiskRates(readBytesPerSecond: 0, writeBytesPerSecond: 20),
            at: Date(timeIntervalSince1970: 3)
        )
        history.record(
            rates: HostDiskRates(readBytesPerSecond: 30, writeBytesPerSecond: 40),
            at: Date(timeIntervalSince1970: 4)
        )
        history.record(
            rates: HostDiskRates(readBytesPerSecond: 50, writeBytesPerSecond: 60),
            at: Date(timeIntervalSince1970: 5)
        )
        XCTAssertEqual(history.read.samples.map(\.value), [0, 30, 50])
        XCTAssertEqual(history.write.samples.map(\.value), [20, 40, 60])

        history.reset()
        XCTAssertTrue(history.read.samples.isEmpty)
        XCTAssertTrue(history.write.samples.isEmpty)
    }

    func testMenuBarFocusStillForcesMemoryFromTheDiskPage() {
        var navigation = DashboardNavigation()
        navigation.select(.disk)
        navigation.focusMemoryPage()
        XCTAssertEqual(navigation.selectedPage, .memory)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))
    }

    func testDiskColumnClickStartsDescending() {
        let disk = ProcessTableSort.defaultSort(for: .memory).selecting(.disk)
        XCTAssertEqual(disk, ProcessTableSort(column: .disk, descending: true))
        XCTAssertEqual(disk.selecting(.disk), ProcessTableSort(column: .disk, descending: false))
        XCTAssertEqual(disk.selecting(.name), ProcessTableSort(column: .name, descending: false))
    }

    private func process(
        pid: Int32,
        name: String,
        read: Double?,
        write: Double?,
        memory: UInt64
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: memory,
            threadCount: 1,
            diskReadBytesPerSecond: read,
            diskWriteBytesPerSecond: write
        )
    }
}
