import XCTest
@testable import SamplingCore

final class MemoryTablePhaseTests: XCTestCase {
    func testToggleOnlyAppearsOnMemoryTab() {
        XCTAssertEqual(MemoryRisingOnlyChrome.toggleTitle, "仅上涨")
        XCTAssertTrue(MemoryRisingOnlyChrome.showsToggle(page: .memory))
        XCTAssertFalse(MemoryRisingOnlyChrome.showsToggle(page: .cpu))
        XCTAssertFalse(MemoryRisingOnlyChrome.showsToggle(page: .network))
        XCTAssertFalse(MemoryRisingOnlyChrome.showsToggle(page: .disk))
        XCTAssertFalse(MemoryRisingOnlyChrome.showsToggle(page: .gpu))
    }

    func testSamplingFailedAndNoProcessBeatRisingEmpty() {
        XCTAssertEqual(
            phase(
                loadState: .sampling,
                processCount: 0,
                visibleCount: 0,
                risingOnly: true
            ),
            .sampling
        )
        XCTAssertEqual(
            phase(
                loadState: .ready,
                processCount: 0,
                visibleCount: 0,
                risingOnly: true,
                processListFailed: true
            ),
            .processListFailed
        )
        XCTAssertEqual(
            phase(
                loadState: .failed,
                processCount: 0,
                visibleCount: 0,
                risingOnly: true
            ),
            .failed
        )
        XCTAssertEqual(
            phase(
                loadState: .ready,
                processCount: 0,
                visibleCount: 0,
                risingOnly: true
            ),
            .empty,
            "无进程 stays the existing empty, not the rising-only two-liner"
        )
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: .sampling))
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: .processListFailed))
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: .failed))
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: .empty))
    }

    func testOffNameFilterEmptyDoesNotBecomeRisingEmpty() {
        let offNameEmpty = phase(
            loadState: .ready,
            processCount: 4,
            visibleCount: 0,
            hasActiveNameFilter: true,
            risingOnly: false
        )
        XCTAssertEqual(offNameEmpty, .nameFilterEmpty)
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: offNameEmpty))
    }

    func testOnEmptyUsesLockedTwoSeparateLines() {
        let onEmpty = phase(
            loadState: .ready,
            processCount: 4,
            visibleCount: 0,
            risingOnly: true
        )
        XCTAssertEqual(onEmpty, .risingOnlyEmpty)

        let lines = MemoryTableEmptyCopy.risingOnlyLines(for: onEmpty)
        XCTAssertEqual(lines?.title, "Top5 暂无上涨")
        XCTAssertEqual(lines?.message, "其他进程未做趋势判断")
        XCTAssertNotEqual(lines?.title, lines?.message)
        XCTAssertNotEqual(
            lines?.title,
            "\(lines?.title ?? "")\(lines?.message ?? "")",
            "title and message stay two lines, not one concatenated sentence"
        )
        XCTAssertFalse((lines?.title ?? "").contains("其他进程"))
        XCTAssertFalse((lines?.title ?? "").contains("当前没有"))
        XCTAssertFalse((lines?.title ?? "").contains("当前排序前 5"))
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: .ready))
    }

    func testOnWithRowsDoesNotPaintEmpty() {
        XCTAssertEqual(
            phase(
                loadState: .ready,
                processCount: 4,
                visibleCount: 2,
                risingOnly: true
            ),
            .ready
        )
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: .ready))
    }

    func testOnPlusNameHideStillUsesRisingEmptyNotNameEmpty() {
        let onNamedEmpty = phase(
            loadState: .ready,
            processCount: 4,
            visibleCount: 0,
            hasActiveNameFilter: true,
            risingOnly: true
        )
        XCTAssertEqual(onNamedEmpty, .risingOnlyEmpty)
        XCTAssertNotEqual(onNamedEmpty, .nameFilterEmpty)
        XCTAssertEqual(
            MemoryTableEmptyCopy.risingOnlyLines(for: onNamedEmpty)?.title,
            MemoryGrowthRisingFilterCopy.emptyTitle
        )
    }

    func testNonMemoryTabsNeverPaintRisingEmpty() {
        for page in [DashboardPage.cpu, .network, .disk, .gpu] {
            XCTAssertEqual(
                phase(
                    page: page,
                    loadState: .ready,
                    processCount: 4,
                    visibleCount: 0,
                    hasActiveNameFilter: true,
                    risingOnly: true
                ),
                .nameFilterEmpty,
                "\(page) must not take the memory rising-only empty"
            )
            XCTAssertFalse(MemoryRisingOnlyChrome.showsToggle(page: page))
        }
    }

    func testOnNameHideKeepsRisingSelectionWhileTableIsEmpty() {
        let rows = [
            process(pid: 1, name: "Busy App", memory: 500),
            process(pid: 2, name: "Helper", memory: 300),
        ]
        let seriesByPid = [Int32(1): risingSeries()]
        let projected = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "Nope",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertTrue(projected.isEmpty)
        XCTAssertEqual(
            phase(
                loadState: .ready,
                processCount: rows.count,
                visibleCount: projected.count,
                hasActiveNameFilter: true,
                risingOnly: true
            ),
            .risingOnlyEmpty
        )
        XCTAssertEqual(
            MemoryGrowthRisingFilter.selectedPid(
                current: 1,
                rows: rows,
                nameQuery: "Nope",
                page: .memory,
                risingOnly: true,
                seriesByPid: seriesByPid
            ),
            1,
            "name-filter hide of a still-rising pid keeps selection"
        )
    }

    func testOnBadgeLossClearsSelectionOnTheSameProjectionBeat() {
        let rows = [process(pid: 7, name: "Fell Out", memory: 80)]
        let projected = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: [:]
        )
        XCTAssertTrue(projected.isEmpty)
        XCTAssertEqual(
            phase(
                loadState: .ready,
                processCount: rows.count,
                visibleCount: projected.count,
                risingOnly: true
            ),
            .risingOnlyEmpty
        )
        XCTAssertNil(
            MemoryGrowthRisingFilter.selectedPid(
                current: 7,
                rows: rows,
                nameQuery: "",
                page: .memory,
                risingOnly: true,
                seriesByPid: [:]
            )
        )
    }

    func testChromeAndEmptyCopyStayCalm() {
        let blob = [
            MemoryRisingOnlyChrome.toggleTitle,
            MemoryGrowthRisingFilterCopy.emptyTitle,
            MemoryGrowthRisingFilterCopy.emptyMessage,
        ].joined(separator: "\n")
        for word in ["泄漏", "泄露", "危险", "告警", "异常", "中招"] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("leak"))
    }

    private func phase(
        page: DashboardPage = .memory,
        loadState: LoadState,
        processCount: Int,
        visibleCount: Int,
        hasActiveNameFilter: Bool = false,
        risingOnly: Bool,
        processListFailed: Bool = false
    ) -> MemoryTablePhase {
        MemoryTablePhaseResolver.resolve(
            page: page,
            loadState: loadState,
            processCount: processCount,
            visibleCount: visibleCount,
            hasActiveNameFilter: hasActiveNameFilter,
            risingOnly: risingOnly,
            processListFailed: processListFailed
        )
    }

    private func risingSeries() -> [ChartSample] {
        let baseline = 200_000_000.0
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<MemoryGrowthSignal.minSamples).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index) * 1.5),
                value: baseline + Double(index) * 1_048_576
            )
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
