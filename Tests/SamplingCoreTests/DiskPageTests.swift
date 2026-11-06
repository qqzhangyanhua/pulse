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
        XCTAssertTrue(DashboardPage.machine.isSelectable)
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

    /// Phase 19 focused checks on SamplingCore. They do not click a Mac header,
    /// do not look at chevrons, and do not instantiate `MemoryDashboardVM`.
    /// Header literals are a source read in `MemoryDashboardVMSortWiringSourceTests`.
    func testPhase19DefaultDiskSortStaysCombinedDescendingForTheLockedTriple() {
        let rows = phase19CombinedTriple()
        let sort = ProcessTableSort.defaultSort(for: .disk)
        XCTAssertEqual(sort, ProcessTableSort(column: .disk, descending: true))
        XCTAssertNotEqual(sort.column, .diskRead)
        XCTAssertNotEqual(sort.column, .diskWrite)
        XCTAssertEqual(rows.map(\.diskSortKey), [0, 100, 90])
        XCTAssertEqual(sort.ordered(rows).map(\.pid), [1, 2, 3])
    }

    func testPhase19SelectingWriteThenReadStartsEachMetricDescending() {
        let rows = phase19CombinedTriple()
        let baseline = ProcessTableSort.defaultSort(for: .disk)

        let writeDescending = baseline.selecting(.diskWrite)
        XCTAssertEqual(writeDescending, ProcessTableSort(column: .diskWrite, descending: true))
        XCTAssertEqual(writeDescending.ordered(rows).map(\.pid), [1, 2, 3])

        let writeAscending = writeDescending.selecting(.diskWrite)
        XCTAssertEqual(writeAscending, ProcessTableSort(column: .diskWrite, descending: false))
        XCTAssertEqual(writeAscending.ordered(rows).map(\.pid), [3, 2, 1])

        let readDescending = writeAscending.selecting(.diskRead)
        XCTAssertEqual(readDescending, ProcessTableSort(column: .diskRead, descending: true))
        XCTAssertEqual(readDescending.ordered(rows).map(\.pid), [2, 1, 3])

        let readAscending = readDescending.selecting(.diskRead)
        XCTAssertEqual(readAscending, ProcessTableSort(column: .diskRead, descending: false))
        XCTAssertEqual(readAscending.ordered(rows).map(\.pid), [1, 3, 2])

        let directRead = baseline.selecting(.diskRead)
        XCTAssertEqual(directRead, ProcessTableSort(column: .diskRead, descending: true))
        XCTAssertEqual(directRead.ordered(rows).map(\.pid), [2, 1, 3])
    }

    func testPhase19MissingReadAndIndependentMissingWriteKeepNilAndRealZero() {
        let readRows = [
            process(pid: 3, name: "P3", read: 0, write: 0, memory: 1),
            process(pid: 1, name: "P1", read: nil, write: 50, memory: 1),
            process(pid: 2, name: "P2", read: 0, write: 20, memory: 1),
        ]
        XCTAssertEqual(readRows.map(\.diskSortKey), [0, -1, 20])
        XCTAssertEqual(DiskRateText.string(nil), "—")
        XCTAssertEqual(DiskRateText.string(0), "0 字节/秒")
        XCTAssertEqual(DiskRateText.string(50), "50 字节/秒")
        XCTAssertEqual(DiskRateText.string(20), "20 字节/秒")
        XCTAssertNotEqual(DiskRateText.string(50), "—")
        XCTAssertNotEqual(DiskRateText.string(50), "0 字节/秒")

        let readDescending = ProcessTableSort(column: .diskRead, descending: true)
        let readAscending = ProcessTableSort(column: .diskRead, descending: false)
        XCTAssertEqual(readDescending.ordered(readRows).map(\.pid), [2, 3, 1])
        XCTAssertEqual(readAscending.ordered(readRows).map(\.pid), [1, 2, 3])

        let writeDescending = ProcessTableSort(column: .diskWrite, descending: true)
        let writeAscending = ProcessTableSort(column: .diskWrite, descending: false)
        XCTAssertEqual(writeDescending.ordered(readRows).map(\.pid), [1, 2, 3])
        XCTAssertEqual(writeAscending.ordered(readRows).map(\.pid), [3, 2, 1])

        let missingRead = readDescending.ordered(readRows).first { $0.pid == 1 }
        XCTAssertNil(missingRead?.diskReadBytesPerSecond)
        XCTAssertEqual(missingRead?.diskWriteBytesPerSecond, 50)
        XCTAssertEqual(DiskRateText.string(missingRead?.diskReadBytesPerSecond), "—")
        XCTAssertEqual(DiskRateText.string(missingRead?.diskWriteBytesPerSecond), "50 字节/秒")
        XCTAssertEqual(readRows.map(\.diskReadBytesPerSecond), [Optional(0), nil, Optional(0)])
        XCTAssertEqual(readRows.map(\.diskWriteBytesPerSecond), [Optional(0), Optional(50), Optional(20)])

        let writeRows = [
            process(pid: 7, name: "P7", read: 0, write: 0, memory: 1),
            process(pid: 4, name: "P4", read: 0, write: nil, memory: 1),
            process(pid: 6, name: "P6", read: 0, write: 10, memory: 1),
            process(pid: 5, name: "P5", read: 0, write: 0, memory: 1),
        ]
        XCTAssertEqual(DiskRateText.string(10), "10 字节/秒")
        XCTAssertEqual(writeDescending.ordered(writeRows).map(\.pid), [6, 5, 7, 4])
        XCTAssertEqual(writeAscending.ordered(writeRows).map(\.pid), [4, 5, 7, 6])

        let missingWrite = writeAscending.ordered(writeRows).first { $0.pid == 4 }
        XCTAssertEqual(missingWrite?.diskReadBytesPerSecond, 0)
        XCTAssertNil(missingWrite?.diskWriteBytesPerSecond)
        XCTAssertEqual(DiskRateText.string(missingWrite?.diskReadBytesPerSecond), "0 字节/秒")
        XCTAssertEqual(DiskRateText.string(missingWrite?.diskWriteBytesPerSecond), "—")
        XCTAssertEqual(
            writeDescending.ordered(writeRows).map(\.diskWriteBytesPerSecond),
            [Optional(10), Optional(0), Optional(0), nil]
        )
        XCTAssertEqual(writeRows.map(\.diskWriteBytesPerSecond), [Optional(0), nil, Optional(10), Optional(0)])
    }

    func testPhase19FilterPrecedesOrderedAndSortLeavesRatesUntouched() {
        let rows = phase19CombinedTriple()
        let named = ProcessNameFilter.apply(rows, query: "b")
        XCTAssertEqual(named.map(\.pid), [2])
        XCTAssertEqual(ProcessTableSort.defaultSort(for: .disk).ordered(named).map(\.pid), [2])

        let blank = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "  ",
            page: .disk,
            risingOnly: false,
            seriesByPid: [:]
        )
        XCTAssertEqual(ProcessTableSort.defaultSort(for: .disk).ordered(blank).map(\.pid), [1, 2, 3])

        let diskRising = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .disk,
            risingOnly: true,
            seriesByPid: [:]
        )
        XCTAssertEqual(diskRising.map(\.pid), rows.map(\.pid))
        XCTAssertEqual(
            ProcessTableSort(column: .diskRead, descending: true).ordered(diskRising).map(\.pid),
            [2, 1, 3]
        )

        let memoryRising = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: [:]
        )
        XCTAssertTrue(memoryRising.isEmpty)

        let before = rows
        let ordered = ProcessTableSort(column: .diskWrite, descending: false).ordered(rows)
        XCTAssertEqual(rows, before)
        XCTAssertEqual(ordered.map(\.pid), [3, 2, 1])
        XCTAssertEqual(ordered.map(\.diskReadBytesPerSecond), [Optional(0), Optional(60), Optional(0)])
        XCTAssertEqual(ordered.map(\.diskWriteBytesPerSecond), [Optional(0), Optional(30), Optional(100)])
    }

    func testPhase19DiskSortDoesNotWriteMemoryPublicationOrMenuBarTop() {
        var publication = MemoryPageSortPublication()
        let memory = ProcessTableSort(column: .memory, descending: true)
        XCTAssertEqual(
            publication.publishMemoryPageSort(memory, selectedPage: .memory),
            .notifySampler(memory)
        )

        let rows = [
            process(pid: 1, name: "aaa", read: 0, write: 100, memory: 10),
            process(pid: 2, name: "bbb", read: 60, write: 0, memory: 30),
            process(pid: 3, name: "ccc", read: 0, write: 50, memory: 20),
        ]
        let diskWrite = ProcessTableSort(column: .diskWrite, descending: true)
        XCTAssertEqual(diskWrite.ordered(rows).map(\.pid), [1, 3, 2])
        XCTAssertEqual(
            publication.publishMemoryPageSort(diskWrite, selectedPage: .disk),
            .skip
        )
        let diskRead = ProcessTableSort(column: .diskRead, descending: false)
        XCTAssertEqual(
            publication.publishMemoryPageSort(diskRead, selectedPage: .disk),
            .skip
        )
        XCTAssertEqual(publication.sort, memory)

        let projected = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: nil,
            samplingFailed: false,
            rows: rows,
            processListFailed: false,
            sort: publication.sort
        )
        XCTAssertEqual(projected.processes.map(\.pid), [2, 3, 1])
        XCTAssertNotEqual(projected.processes.map(\.pid), diskWrite.ordered(rows).map(\.pid))
        XCTAssertEqual(
            Array(publication.sort.ordered(rows).prefix(MenuBarPopoverShell.maxProcessRows).map(\.pid)),
            projected.processes.map(\.pid)
        )
    }

    func testPhase19ReselectingDiskKeepsHandPickedReadOrWriteSort() {
        var navigation = DashboardNavigation()
        navigation.select(.disk)
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .disk, descending: true))

        let write = navigation.sort.selecting(.diskWrite)
        navigation.updateSort(write)
        navigation.select(.disk)
        XCTAssertEqual(navigation.selectedPage, .disk)
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .diskWrite, descending: true))

        let read = navigation.sort.selecting(.diskRead)
        navigation.updateSort(read)
        navigation.select(.disk)
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .diskRead, descending: true))

        navigation.select(.gpu)
        XCTAssertEqual(navigation.selectedPage, .disk)
        XCTAssertEqual(navigation.sort.column, .diskRead)

        navigation.focusMemoryPage()
        XCTAssertEqual(navigation.selectedPage, .memory)
        XCTAssertEqual(navigation.sort, ProcessTableSort.defaultSort(for: .memory))
    }

    /// Locked triple, deliberately not pre-sorted. Names `aaa` / `bbb` / `ccc` feed the filter case.
    private func phase19CombinedTriple() -> [ProcessRow] {
        [
            process(pid: 3, name: "ccc", read: 0, write: 0, memory: 1),
            process(pid: 1, name: "aaa", read: 0, write: 100, memory: 1),
            process(pid: 2, name: "bbb", read: 60, write: 30, memory: 1),
        ]
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
