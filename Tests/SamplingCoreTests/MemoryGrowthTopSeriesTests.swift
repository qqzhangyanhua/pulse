import XCTest
@testable import SamplingCore

final class MemoryGrowthTopSeriesTests: XCTestCase {
    private let memorySort = ProcessTableSort.defaultSort(for: .memory)
    private let tick = Date(timeIntervalSince1970: 1_700_000_000)

    func testPidLimitIsHardCappedAtFive() {
        XCTAssertEqual(MemoryGrowthTopSeries.pidLimit, 5)
        XCTAssertEqual(MemoryGrowthTopSeries.seriesLimit, 90)
        XCTAssertEqual(MemoryGrowthTopSeries.seriesLimit, ChartSampleRing.limit)
    }

    func testPidsTakeTheCurrentMemorySortTopFive() {
        let rows = rankedRows(memories: [10, 90, 80, 70, 60, 50, 40])
        XCTAssertEqual(
            MemoryGrowthTopSeries.pids(from: rows, sort: memorySort),
            [2, 3, 4, 5, 6]
        )
    }

    func testPidsFollowNameSortNotTheViewportOrAFilter() {
        let rows = [
            process(pid: 1, name: "Zebra", memory: 900),
            process(pid: 2, name: "Alpha", memory: 100),
            process(pid: 3, name: "Middle", memory: 500),
            process(pid: 4, name: "Beta", memory: 800),
            process(pid: 5, name: "Gamma", memory: 200),
            process(pid: 6, name: "Hidden", memory: 700),
        ]
        let nameSort = ProcessTableSort(column: .name, descending: false)
        XCTAssertEqual(
            MemoryGrowthTopSeries.pids(from: rows, sort: nameSort),
            [2, 4, 5, 6, 3]
        )

        let filtered = ProcessNameFilter.apply(rows, query: "Zebra")
        XCTAssertEqual(filtered.map(\.pid), [1])
        XCTAssertEqual(
            MemoryGrowthTopSeries.pids(from: rows, sort: memorySort),
            [1, 4, 6, 3, 5],
            "Top 5 is the unfiltered table sort, not visibleRows"
        )
    }

    func testFewerThanFiveRowsKeepsThePresentPids() {
        let rows = rankedRows(memories: [30, 20])
        XCTAssertEqual(MemoryGrowthTopSeries.pids(from: rows, sort: memorySort), [1, 2])
        XCTAssertEqual(MemoryGrowthTopSeries.pids(from: [], sort: memorySort), [])
    }

    func testAdvanceDoesNotKeepASixthPidEvenWhenSixArePassed() {
        var store = MemoryGrowthTopStore()
        var nextID: UInt64 = 1
        let extra = Array(Int32(1)...6)
        store.advance(
            values: Dictionary(uniqueKeysWithValues: extra.map { ($0, Double($0) * 1_000) }),
            topPids: extra,
            at: tick,
            nextSampleID: &nextID
        )
        XCTAssertEqual(store.seriesByPid.count, 5)
        XCTAssertNil(store.series(for: 6))
        XCTAssertEqual(Set(store.seriesByPid.keys), Set(Array(Int32(1)...5)))
    }

    func testTopFiveRisingSeriesCanEvaluateRising() {
        var store = MemoryGrowthTopStore()
        let top = Array(Int32(1)...5)
        fill(store: &store, pids: top, count: MemoryGrowthSignal.minSamples, step: 1_048_576)

        XCTAssertEqual(store.seriesByPid.count, 5)
        for pid in top {
            let series = store.series(for: pid)
            XCTAssertEqual(MemoryGrowthSignal.evaluate(series ?? []), .rising, "pid \(pid)")
            XCTAssertEqual(
                MemoryGrowthList.badge(page: .memory, rowPid: pid, seriesByPid: store.seriesByPid),
                MemoryGrowthListBadge(
                    title: MemoryGrowthListCopy.title,
                    help: MemoryGrowthListCopy.help
                ),
                "pid \(pid)"
            )
        }
    }

    func testOutsideTopFiveIsNotMaintainedAndHasNoBadge() {
        var store = MemoryGrowthTopStore()
        fill(store: &store, pids: [1, 2, 3, 4, 5], count: MemoryGrowthSignal.minSamples, step: 1_048_576)

        XCTAssertNil(store.series(for: 99))
        XCTAssertNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 99, seriesByPid: store.seriesByPid)
        )

        var nextID: UInt64 = 10_000
        store.advance(
            values: [99: 500_000_000],
            topPids: [1, 2, 3, 4, 5],
            at: tick,
            nextSampleID: &nextID
        )
        XCTAssertNil(store.series(for: 99), "a value outside topPids is ignored")
        XCTAssertEqual(nextID, 10_000, "no sample is consumed for an out-of-set pid")
    }

    func testInsufficientAndNoneDoNotLightTheBadge() {
        var shortStore = MemoryGrowthTopStore()
        fill(store: &shortStore, pids: [7], count: 12, step: 8_388_608)
        let short = shortStore.series(for: 7) ?? []
        XCTAssertEqual(MemoryGrowthSignal.evaluate(short), .insufficient)
        XCTAssertNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 7, seriesByPid: shortStore.seriesByPid)
        )

        var flatStore = MemoryGrowthTopStore()
        fill(store: &flatStore, pids: [7], count: 90, step: 0)
        let flat = flatStore.series(for: 7) ?? []
        XCTAssertEqual(MemoryGrowthSignal.evaluate(flat), .none)
        XCTAssertNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 7, seriesByPid: flatStore.seriesByPid)
        )

        XCTAssertNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 7, seriesByPid: [:])
        )
    }

    func testSortChurnDropsTheFallenPidSeriesImmediately() {
        var store = MemoryGrowthTopStore()
        fill(store: &store, pids: [1, 2, 3, 4, 5], count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(store.series(for: 5) ?? []), .rising)
        XCTAssertNotNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 5, seriesByPid: store.seriesByPid)
        )

        store.retain(only: [1, 2, 3, 4, 8])
        XCTAssertNil(store.series(for: 5))
        XCTAssertNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 5, seriesByPid: store.seriesByPid)
        )
        XCTAssertNil(store.series(for: 8), "a newly entered pid has no leftover series")
        XCTAssertEqual(Set(store.seriesByPid.keys), Set([1, 2, 3, 4]))
    }

    func testAdvanceAlsoDropsAPidThatFellOutThisTick() {
        var store = MemoryGrowthTopStore()
        fill(store: &store, pids: [1, 2, 3, 4, 5], count: 4, step: 1_000)
        XCTAssertNotNil(store.series(for: 5))

        var nextID: UInt64 = 500
        store.advance(
            values: [1: 10, 2: 20, 3: 30, 4: 40, 9: 90],
            topPids: [1, 2, 3, 4, 9],
            at: tick.addingTimeInterval(1.5),
            nextSampleID: &nextID
        )
        XCTAssertNil(store.series(for: 5))
        XCTAssertEqual(store.series(for: 1)?.count, 5)
        XCTAssertEqual(store.series(for: 9)?.count, 1)
        XCTAssertEqual(Set(store.seriesByPid.keys), Set([1, 2, 3, 4, 9]))
    }

    func testMissingValueForATopPidDropsThatSeries() {
        var store = MemoryGrowthTopStore()
        fill(store: &store, pids: [1, 2], count: 3, step: 1_000)
        var nextID: UInt64 = 80
        store.advance(
            values: [1: 4_000],
            topPids: [1, 2],
            at: tick,
            nextSampleID: &nextID
        )
        XCTAssertNotNil(store.series(for: 1))
        XCTAssertNil(store.series(for: 2))
    }

    func testBadgeUsesEvaluateAndDoesNotInventASecondRise() {
        XCTAssertEqual(MemoryGrowthSignal.minSamples, 80)
        XCTAssertEqual(MemoryGrowthSignal.deltaThreshold, 8 * 1024 * 1024)
        XCTAssertEqual(MemoryGrowthSignal.riseFloor, 0.6)

        let rising = climbingSeries(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        let twoPointHack = climbingSeries(count: 2, step: 50_000_000)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(rising), .rising)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(twoPointHack), .insufficient)

        let store = [Int32(3): rising, Int32(4): twoPointHack]
        XCTAssertNotNil(MemoryGrowthList.badge(page: .memory, rowPid: 3, seriesByPid: store))
        XCTAssertNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 4, seriesByPid: store),
            "a two-point rss delta must not light the badge"
        )
        XCTAssertEqual(
            MemoryGrowthList.badge(page: .memory, rowPid: 3, seriesByPid: store) != nil,
            MemoryGrowthSignal.evaluate(rising) == .rising
        )
    }

    func testNonMemoryPagesNeverShowTheTopFiveBadge() {
        let rising = climbingSeries(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        let store = [Int32(3): rising]
        for page in [DashboardPage.cpu, .disk, .network, .gpu] {
            XCTAssertNil(
                MemoryGrowthList.badge(page: page, rowPid: 3, seriesByPid: store),
                page.rawValue
            )
        }
    }

    func testSelectedOnlyBadgeIsUnchangedWhenTopFiveWouldRise() {
        let rising = climbingSeries(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        let selected = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 3,
            selectedPid: 3,
            detailSeries: rising
        )
        let unselected = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 3,
            selectedPid: 9,
            detailSeries: rising
        )
        XCTAssertEqual(selected?.title, MemoryGrowthListCopy.title)
        XCTAssertNil(unselected, "list UI wiring stays selected-only until phase 9②")
    }

    func testAdoptKeepsTheLongerSelectedSeriesWhenAPidEntersTopFive() {
        var store = MemoryGrowthTopStore()
        fill(store: &store, pids: [1, 2, 3, 4, 9], count: 3, step: 1_000)
        XCTAssertEqual(store.series(for: 9)?.count, 3)

        let selectedHistory = climbingSeries(count: 20, step: 1_048_576)
        store.adopt(pid: 9, series: selectedHistory)
        var nextID: UInt64 = 9_000
        store.advance(
            values: [1: 10, 2: 20, 3: 30, 4: 40, 9: selectedHistory.last!.value + 1_048_576],
            topPids: [1, 2, 3, 4, 9],
            at: tick.addingTimeInterval(30),
            nextSampleID: &nextID
        )
        XCTAssertEqual(store.series(for: 9)?.count, 21)
        XCTAssertEqual(store.series(for: 9)?.first?.value, selectedHistory.first?.value)
    }

    func testRingHelperMatchesTheSelectedDetailWindow() {
        var series: [ChartSample] = []
        for index in 0..<100 {
            ChartSampleRing.append(
                Double(index),
                at: tick.addingTimeInterval(Double(index)),
                id: UInt64(index + 1),
                to: &series
            )
        }
        XCTAssertEqual(series.count, 90)
        XCTAssertEqual(series.first?.value, 10)
        XCTAssertEqual(series.last?.value, 99)
    }

    func testCopyDoesNotClaimALeakOrDanger() {
        let blob = [
            MemoryGrowthListCopy.title,
            MemoryGrowthListCopy.help,
        ].joined(separator: "\n")
        for word in ["泄漏", "泄露", "危险", "告警"] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("leak"))
    }

    private func fill(
        store: inout MemoryGrowthTopStore,
        pids: [Int32],
        count: Int,
        step: Double
    ) {
        var nextID: UInt64 = 1
        let baseline = 200_000_000.0
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

    private func climbingSeries(count: Int, step: Double) -> [ChartSample] {
        let baseline = 200_000_000.0
        return (0..<count).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: tick.addingTimeInterval(Double(index) * 1.5),
                value: baseline + Double(index) * step
            )
        }
    }

    private func rankedRows(memories: [UInt64]) -> [ProcessRow] {
        memories.enumerated().map { index, memory in
            process(pid: Int32(index + 1), name: "P\(index + 1)", memory: memory)
        }
    }

    private func process(pid: Int32, name: String, memory: UInt64) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: memory,
            threadCount: 1
        )
    }
}
