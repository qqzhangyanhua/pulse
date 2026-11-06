import XCTest
@testable import SamplingCore

/// Phase 12 step 1: memory-tab rising-only table projection + selection.
/// Predicate is the existing list badge. No second growth math. No UI.
final class MemoryGrowthRisingFilterTests: XCTestCase {
    private let memorySort = ProcessTableSort.defaultSort(for: .memory)
    private let nameSort = ProcessTableSort(column: .name, descending: false)

    func testDefaultOffKeepsTheNameFilteredTable() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()

        let off = MemoryGrowthRisingFilter.ordered(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: false,
            seriesByPid: seriesByPid,
            sort: memorySort
        )
        XCTAssertEqual(off.map(\.pid), memorySort.ordered(rows).map(\.pid))
        XCTAssertEqual(off.count, rows.count)

        let namedOff = MemoryGrowthRisingFilter.ordered(
            rows: rows,
            nameQuery: "App",
            page: .memory,
            risingOnly: false,
            seriesByPid: seriesByPid,
            sort: memorySort
        )
        XCTAssertEqual(namedOff.map(\.pid), [1, 6, 3])
    }

    func testOnKeepsOnlyBadgeRisingRows() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()

        XCTAssertEqual(MemoryGrowthSignal.evaluate(seriesByPid[1]!), .rising)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(seriesByPid[3]!), .none)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(seriesByPid[4]!), .insufficient)
        XCTAssertNil(seriesByPid[6])

        let on = MemoryGrowthRisingFilter.ordered(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid,
            sort: memorySort
        )
        XCTAssertEqual(on.map(\.pid), [1, 2])
        XCTAssertFalse(on.contains(where: { $0.pid == 3 }), ".none must not enter and is not labeled 非上涨")
        XCTAssertFalse(on.contains(where: { $0.pid == 4 }), ".insufficient must not enter")
        XCTAssertFalse(on.contains(where: { $0.pid == 6 }), "no series must not enter")
        XCTAssertFalse(on.contains(where: { $0.pid == 99 }), "selected-but-outside-Top5 must not enter")
    }

    func testOnPredicateIsTheExistingListBadgeNotASecondMath() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()
        let on = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )

        for row in rows {
            let badge = MemoryGrowthList.badge(
                page: .memory,
                rowPid: row.pid,
                seriesByPid: seriesByPid
            )
            XCTAssertEqual(
                on.contains(where: { $0.pid == row.pid }),
                badge != nil,
                "pid \(row.pid)"
            )
            XCTAssertEqual(
                badge != nil,
                MemoryGrowthSignal.evaluate(seriesByPid[row.pid] ?? []) == .rising
                    && seriesByPid[row.pid] != nil,
                "pid \(row.pid) must reuse evaluate == .rising via the badge"
            )
        }

        let twoPointHack = series(count: 2, step: 50_000_000)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(twoPointHack), .insufficient)
        XCTAssertTrue(
            MemoryGrowthRisingFilter.apply(
                rows: [process(pid: 8, name: "Hack", memory: 900)],
                nameQuery: "",
                page: .memory,
                risingOnly: true,
                seriesByPid: [8: twoPointHack]
            ).isEmpty,
            "a two-point rss delta must not enter the ON table"
        )
    }

    func testOnDoesNotUseSelectedDetailSeriesAsASecondSource() {
        let rows = fixtureRows()
        let selectedRising = risingSeries()
        XCTAssertEqual(MemoryGrowthSignal.evaluate(selectedRising), .rising)

        let on = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: [1: risingSeries(), 3: flatSeries()]
        )
        XCTAssertEqual(on.map(\.pid), [1])
        XCTAssertFalse(
            on.contains(where: { $0.pid == 99 }),
            "detail selectedMemorySeries must not admit a pid outside topMemorySeries"
        )
        XCTAssertNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 99, seriesByPid: [1: selectedRising])
        )
        XCTAssertEqual(
            MemoryGrowthSidebar.slot(page: .memory, selectedPid: 99, detailSeries: selectedRising)?.caption,
            MemoryGrowthCopy.rising,
            "sidebar may still rise on the detail ring; the table filter must ignore that ring"
        )
    }

    /// 0–5 is the TopStore contract, not a second `prefix` on the table projection.
    /// Passing six pids into `advance` still leaves five keys; the filter only sees that map.
    func testRisingOnlyBoundComesFromTopStoreNotASecondPrefix() {
        XCTAssertEqual(MemoryGrowthTopSeries.pidLimit, 5)

        var store = MemoryGrowthTopStore()
        fill(store: &store, pids: Array(Int32(1)...6), count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        XCTAssertEqual(store.seriesByPid.count, 5)
        XCTAssertNil(store.series(for: 6), "TopStore.advance hard-caps; pid 6 never becomes a badge source")
        XCTAssertEqual(Set(store.seriesByPid.keys), Set(Array(Int32(1)...5)))

        let rows = (1...8).map { process(pid: Int32($0), name: "P\($0)", memory: UInt64(90 - $0)) }
        XCTAssertEqual(
            MemoryGrowthTopSeries.pids(from: rows, sort: memorySort).count,
            MemoryGrowthTopSeries.pidLimit
        )

        let on = MemoryGrowthRisingFilter.ordered(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: store.seriesByPid,
            sort: nameSort
        )
        XCTAssertEqual(Set(on.map(\.pid)), Set(store.seriesByPid.keys))
        XCTAssertEqual(on.count, 5)
        XCTAssertEqual(on.map(\.name), ["P1", "P2", "P3", "P4", "P5"])
        XCTAssertFalse(on.contains(where: { $0.pid == 6 }))
        for pid in on.map(\.pid) {
            XCTAssertNotNil(
                MemoryGrowthList.badge(page: .memory, rowPid: pid, seriesByPid: store.seriesByPid)
            )
        }
    }

    func testOnEmptyTableWhenNothingIsRising() {
        let rows = fixtureRows()
        let empty = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: [:]
        )
        XCTAssertTrue(empty.isEmpty)

        let noneOnly = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: [1: flatSeries(), 2: shortSeries()]
        )
        XCTAssertTrue(noneOnly.isEmpty)
        XCTAssertTrue(
            MemoryGrowthRisingFilter.isRisingOnlyEmpty(
                page: .memory,
                risingOnly: true,
                projectedCount: noneOnly.count
            )
        )
        XCTAssertFalse(
            MemoryGrowthRisingFilter.isRisingOnlyEmpty(
                page: .memory,
                risingOnly: false,
                projectedCount: 0
            ),
            "OFF empty is not the rising-only empty"
        )
    }

    func testNameFilterRunsBeforeRisingAndDoesNotChangeNameSelection() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()

        let namedOn = MemoryGrowthRisingFilter.ordered(
            rows: rows,
            nameQuery: "App",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid,
            sort: memorySort
        )
        XCTAssertEqual(namedOn.map(\.pid), [1])
        XCTAssertFalse(namedOn.contains(where: { $0.pid == 2 }), "rising Helper is hidden by the name filter")

        let selectedOff = MemoryGrowthRisingFilter.selectedPid(
            current: 6,
            rows: rows,
            nameQuery: "Nope",
            page: .memory,
            risingOnly: false,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(selectedOff, 6, "name-filter hide must keep selectedPid against the full rows")
        XCTAssertEqual(ProcessSelection.acceptedPid(6, in: rows), 6)
        XCTAssertNil(ProcessNameFilter.apply(rows, query: "Nope").first { $0.pid == 6 })

        XCTAssertEqual(
            MemoryGrowthList.badge(page: .memory, rowPid: 1, seriesByPid: seriesByPid)?.title,
            MemoryGrowthListCopy.title
        )
        let namedTable = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "Nope",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertTrue(namedTable.isEmpty, "name filter runs first and can hide a rising row")

        let selectedOn = MemoryGrowthRisingFilter.selectedPid(
            current: 1,
            rows: rows,
            nameQuery: "Nope",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(selectedOn, 1, "ON + name-hide of a rising pid must keep selectedPid")
        XCTAssertEqual(ProcessSelection.acceptedPid(1, in: rows), 1)
        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: selectedOn, rows: rows), 1)
    }

    func testSortStillAppliesAfterTheRisingKeep() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()

        let byName = MemoryGrowthRisingFilter.ordered(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid,
            sort: nameSort
        )
        XCTAssertEqual(byName.map(\.name), ["Busy App", "Helper"])
        XCTAssertNotEqual(byName.map(\.pid), [1, 2].reversed())

        let offByName = MemoryGrowthRisingFilter.ordered(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: false,
            seriesByPid: seriesByPid,
            sort: nameSort
        )
        XCTAssertEqual(offByName.map(\.pid), nameSort.ordered(rows).map(\.pid))
    }

    func testOtherPagesIgnoreTheMemorySwitch() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()
        let cpuSort = ProcessTableSort.defaultSort(for: .cpu)

        for page in [DashboardPage.cpu, .network, .disk, .gpu] {
            let projected = MemoryGrowthRisingFilter.ordered(
                rows: rows,
                nameQuery: "",
                page: page,
                risingOnly: true,
                seriesByPid: seriesByPid,
                sort: ProcessTableSort.defaultSort(for: page)
            )
            XCTAssertEqual(
                projected.map(\.pid),
                ProcessTableSort.defaultSort(for: page).ordered(rows).map(\.pid),
                page.rawValue
            )
        }

        let cpuNamed = MemoryGrowthRisingFilter.ordered(
            rows: rows,
            nameQuery: "App",
            page: .cpu,
            risingOnly: true,
            seriesByPid: seriesByPid,
            sort: cpuSort
        )
        XCTAssertEqual(cpuNamed.map(\.pid), [1, 3, 6])
    }

    func testTopFiveAndMenuBarStillEatTheUnfilteredRows() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()
        let filtered = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(filtered.map(\.pid), [1, 2])

        XCTAssertEqual(
            MemoryGrowthTopSeries.pids(from: rows, sort: memorySort),
            [1, 6, 2, 3, 4],
            "Top 5 input is the full table sort, never the rising-only slice"
        )
        XCTAssertNotEqual(
            MemoryGrowthTopSeries.pids(from: filtered, sort: memorySort),
            MemoryGrowthTopSeries.pids(from: rows, sort: memorySort)
        )

        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: 4_294_967_296,
            samplingFailed: false,
            rows: rows,
            processListFailed: false
        )
        XCTAssertEqual(strip.processes.map(\.pid), [1, 6, 2])
        XCTAssertNotEqual(strip.processes.map(\.pid), filtered.prefix(3).map(\.pid))
    }

    func testOnClearsAHiddenSelectionAndQuitLosesThatTarget() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()

        let hidden = MemoryGrowthRisingFilter.selectedPid(
            current: 6,
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertNil(hidden, "no-series / outside rising keep must clear selectedPid this beat")
        XCTAssertNil(
            ProcessSelection.scrollTarget(selectedPid: hidden, rows: rows),
            "sidebar / quit must not stay locked on the hidden pid"
        )
        XCTAssertEqual(ProcessSelection.acceptedPid(6, in: rows), 6)
        XCTAssertNil(
            hidden,
            "Quit / Force Quit read selectedPid; clearing it drops the stale sidebar target"
        )

        let outsideTopFive = MemoryGrowthRisingFilter.selectedPid(
            current: 99,
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertNil(outsideTopFive)
        XCTAssertEqual(
            MemoryGrowthSidebar.slot(page: .memory, selectedPid: outsideTopFive, detailSeries: risingSeries()),
            nil,
            "clearing selectedPid drops the sidebar slot this beat"
        )

        let nonePid = MemoryGrowthRisingFilter.selectedPid(
            current: 3,
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertNil(nonePid)

        let insufficientPid = MemoryGrowthRisingFilter.selectedPid(
            current: 4,
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertNil(insufficientPid)
    }

    func testOnClearsWhenThePidLeavesTheTopStoreMap() {
        let rows = fixtureRows()
        var store = MemoryGrowthTopStore()
        fill(store: &store, pids: [1, 2, 3, 4, 5], count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        XCTAssertNotNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 1, seriesByPid: store.seriesByPid)
        )
        XCTAssertEqual(
            MemoryGrowthRisingFilter.selectedPid(
                current: 1,
                rows: rows,
                nameQuery: "",
                page: .memory,
                risingOnly: true,
                seriesByPid: store.seriesByPid
            ),
            1
        )

        store.retain(only: [2, 3, 4, 5, 8])
        XCTAssertNil(store.series(for: 1))
        XCTAssertNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 1, seriesByPid: store.seriesByPid)
        )
        XCTAssertNil(
            MemoryGrowthRisingFilter.selectedPid(
                current: 1,
                rows: rows,
                nameQuery: "",
                page: .memory,
                risingOnly: true,
                seriesByPid: store.seriesByPid
            ),
            "falling out of TopStore drops the badge and must clear selectedPid"
        )
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: nil, rows: rows))
    }

    func testRemainingRisingRowsStaySelectableAndQuittable() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()
        let visible = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(visible.map(\.pid), [1, 2])

        XCTAssertEqual(ProcessSelection.acceptedPid(2, in: visible), 2)
        XCTAssertEqual(
            MemoryGrowthRisingFilter.selectedPid(
                current: 2,
                rows: rows,
                nameQuery: "",
                page: .memory,
                risingOnly: true,
                seriesByPid: seriesByPid
            ),
            2
        )
        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: 2, rows: rows), 2)
        XCTAssertEqual(ProcessSelection.acceptedPid(2, in: rows), 2)
    }

    func testOffDoesNotRestoreASelectionThisSwitchCleared() {
        let rows = fixtureRows()
        let seriesByPid = mixedSeriesByPid()

        let cleared = MemoryGrowthRisingFilter.selectedPid(
            current: 6,
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertNil(cleared)

        let stillCleared = MemoryGrowthRisingFilter.selectedPid(
            current: cleared,
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: false,
            seriesByPid: seriesByPid
        )
        XCTAssertNil(stillCleared, "OFF must not resurrect the pid this switch cleared")
        XCTAssertEqual(
            MemoryGrowthRisingFilter.selectedPid(
                current: 6,
                rows: rows,
                nameQuery: "",
                page: .memory,
                risingOnly: false,
                seriesByPid: seriesByPid
            ),
            6,
            "OFF itself does not rewrite an existing selection"
        )
    }

    func testEmptyCopyIsTheLockedTwoLineCoverageLine() {
        XCTAssertEqual(MemoryGrowthRisingFilterCopy.emptyTitle, "Top5 暂无上涨")
        XCTAssertEqual(MemoryGrowthRisingFilterCopy.emptyMessage, "其他进程未做趋势判断")
        XCTAssertNotEqual(MemoryGrowthRisingFilterCopy.emptyTitle, "当前没有持续上涨的进程")
        XCTAssertFalse(MemoryGrowthRisingFilterCopy.emptyTitle.contains("当前排序前 5"))
        XCTAssertFalse(MemoryGrowthRisingFilterCopy.emptyTitle.contains("当前没有"))
        XCTAssertFalse(MemoryGrowthRisingFilterCopy.emptyMessage.contains("当前没有"))
        XCTAssertNotEqual(
            MemoryGrowthRisingFilterCopy.emptyTitle,
            "当前排序前 5 暂无持续上涨；其他进程未做趋势判断。"
        )

        let blob = [
            MemoryGrowthRisingFilterCopy.emptyTitle,
            MemoryGrowthRisingFilterCopy.emptyMessage,
        ].joined(separator: "\n")
        for word in ["泄漏", "泄露", "危险", "告警"] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("leak"))
    }

    func testProcessRowHasNoIsRisingField() {
        let labels = Mirror(reflecting: process(pid: 1, name: "A", memory: 1)).children.compactMap(\.label)
        XCTAssertFalse(labels.contains("isRising"))
        XCTAssertTrue(labels.contains("memoryBytes"))
    }

    private func fixtureRows() -> [ProcessRow] {
        [
            process(pid: 1, name: "Busy App", memory: 500, cpu: 10),
            process(pid: 2, name: "Helper", memory: 300, cpu: 40),
            process(pid: 3, name: "Flat App", memory: 200, cpu: 5),
            process(pid: 4, name: "Short", memory: 150, cpu: 1),
            process(pid: 6, name: "Quiet App", memory: 400, cpu: 2),
            process(pid: 99, name: "Outside", memory: 50, cpu: 8),
        ]
    }

    private func mixedSeriesByPid() -> [Int32: [ChartSample]] {
        [
            1: risingSeries(),
            2: risingSeries(),
            3: flatSeries(),
            4: shortSeries(),
            5: risingSeries(),
        ]
    }

    private func fill(
        store: inout MemoryGrowthTopStore,
        pids: [Int32],
        count: Int,
        step: Double
    ) {
        var nextID: UInt64 = 1
        let baseline = 200_000_000.0
        let tick = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            var values: [Int32: Double] = [:]
            for pid in pids {
                values[pid] = baseline + Double(index) * step
            }
            store.advance(
                values: values,
                topPids: pids,
                at: tick.addingTimeInterval(Double(index) * 1.5),
                nextSampleID: &nextID
            )
        }
    }

    private func risingSeries() -> [ChartSample] {
        series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
    }

    private func flatSeries() -> [ChartSample] {
        series(count: 90, step: 0)
    }

    private func shortSeries() -> [ChartSample] {
        series(count: 12, step: 8_388_608)
    }

    private func series(count: Int, step: Double) -> [ChartSample] {
        let baseline = 200_000_000.0
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index) * 1.5),
                value: baseline + Double(index) * step
            )
        }
    }

    private func process(pid: Int32, name: String, memory: UInt64, cpu: Double? = nil) -> ProcessRow {
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
}
