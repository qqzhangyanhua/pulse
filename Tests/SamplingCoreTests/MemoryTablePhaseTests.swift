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

    func testNamePlusRisingEmptyUsesNameFilterEmptyCopy() {
        let onNamedEmpty = phase(
            loadState: .ready,
            processCount: 4,
            visibleCount: 0,
            hasActiveNameFilter: true,
            risingOnly: true
        )
        let nameOnly = phase(
            loadState: .ready,
            processCount: 4,
            visibleCount: 0,
            hasActiveNameFilter: true,
            risingOnly: false
        )
        XCTAssertEqual(onNamedEmpty, .nameFilterEmpty)
        XCTAssertNotEqual(onNamedEmpty, .risingOnlyEmpty)
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: onNamedEmpty))

        let lines = MemoryTableEmptyCopy.filterEmptyLines(for: onNamedEmpty)
        let nameOnlyLines = MemoryTableEmptyCopy.filterEmptyLines(for: nameOnly)
        XCTAssertEqual(lines?.title, "没有匹配的 App")
        XCTAssertEqual(lines?.message, "清空名称和仅上涨过滤。")
        XCTAssertEqual(lines?.buttonTitle, "清空过滤")
        XCTAssertEqual(lines?.title, nameOnlyLines?.title)
        XCTAssertEqual(lines?.message, nameOnlyLines?.message)
        XCTAssertEqual(lines?.buttonTitle, nameOnlyLines?.buttonTitle)
        XCTAssertNotEqual(lines?.title, "Top5 暂无上涨")
        XCTAssertNotEqual(lines?.message, "其他进程未做趋势判断")
        XCTAssertNotEqual(lines?.message, "换个名称试试，或清空过滤。")
        XCTAssertNotEqual(lines?.message, "清空名称和仅上涨过滤")
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
            XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: .nameFilterEmpty))
            XCTAssertFalse(MemoryRisingOnlyChrome.showsToggle(page: page))
            XCTAssertEqual(
                phase(
                    page: page,
                    loadState: .ready,
                    processCount: 4,
                    visibleCount: 0,
                    hasActiveNameFilter: false,
                    risingOnly: true
                ),
                .empty,
                "\(page) rising-only without a name filter is not the memory empty"
            )
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
        let hiddenPhase = phase(
            loadState: .ready,
            processCount: rows.count,
            visibleCount: projected.count,
            hasActiveNameFilter: true,
            risingOnly: true
        )
        XCTAssertEqual(hiddenPhase, .nameFilterEmpty)
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: hiddenPhase))
        XCTAssertEqual(
            MemoryTableEmptyCopy.filterEmptyLines(for: hiddenPhase)?.title,
            "没有匹配的 App"
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
        let nameLines = MemoryTableEmptyCopy.filterEmptyLines(for: .nameFilterEmpty)
        let risingLines = MemoryTableEmptyCopy.filterEmptyLines(for: .risingOnlyEmpty)
        let blob = [
            MemoryRisingOnlyChrome.toggleTitle,
            MemoryGrowthRisingFilterCopy.emptyTitle,
            MemoryGrowthRisingFilterCopy.emptyMessage,
            nameLines?.title,
            nameLines?.message,
            nameLines?.buttonTitle,
            risingLines?.title,
            risingLines?.message,
            risingLines?.buttonTitle,
        ].compactMap { $0 }.joined(separator: "\n")
        for word in ["泄漏", "泄露", "危险", "危急", "告警", "异常", "中招"] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("leak"))
    }

    func testPureRisingOnlyEmptyLocksOriginalLinesAndClearButton() {
        let onEmpty = phase(
            loadState: .ready,
            processCount: 4,
            visibleCount: 0,
            hasActiveNameFilter: false,
            risingOnly: true
        )
        XCTAssertEqual(onEmpty, .risingOnlyEmpty)

        let legacy = MemoryTableEmptyCopy.risingOnlyLines(for: onEmpty)
        XCTAssertEqual(legacy?.title, "Top5 暂无上涨")
        XCTAssertEqual(legacy?.message, "其他进程未做趋势判断")

        let lines = MemoryTableEmptyCopy.filterEmptyLines(for: onEmpty)
        XCTAssertEqual(lines?.title, "Top5 暂无上涨")
        XCTAssertEqual(lines?.message, "其他进程未做趋势判断")
        XCTAssertEqual(lines?.buttonTitle, "清空过滤")
        XCTAssertEqual(lines?.title, legacy?.title)
        XCTAssertEqual(lines?.message, legacy?.message)
        XCTAssertNotEqual(lines?.message, "清空名称和仅上涨过滤。")
        XCTAssertNotEqual(lines?.title, "没有匹配的 App")
    }

    func testNameOnlyEmptyLocksClearCopyAndHidesRisingLines() {
        let nameOnly = phase(
            loadState: .ready,
            processCount: 4,
            visibleCount: 0,
            hasActiveNameFilter: true,
            risingOnly: false
        )
        XCTAssertEqual(nameOnly, .nameFilterEmpty)
        XCTAssertNotEqual(nameOnly, .risingOnlyEmpty)
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: nameOnly))

        let lines = MemoryTableEmptyCopy.filterEmptyLines(for: nameOnly)
        XCTAssertEqual(lines?.title, "没有匹配的 App")
        XCTAssertEqual(lines?.message, "清空名称和仅上涨过滤。")
        XCTAssertEqual(lines?.buttonTitle, "清空过滤")
        XCTAssertNotEqual(lines?.title, "Top5 暂无上涨")
        XCTAssertNotEqual(lines?.message, "其他进程未做趋势判断")
        XCTAssertNotEqual(lines?.message, "换个名称试试，或清空过滤。")
    }

    func testSamplingFailureListFailureAndNoProcessBeatNameAndRisingFilters() {
        let gates: [(LoadState, Bool, MemoryTablePhase)] = [
            (.sampling, false, .sampling),
            (.ready, true, .processListFailed),
            (.failed, false, .failed),
            (.ready, false, .empty),
        ]
        for (loadState, processListFailed, expected) in gates {
            for risingOnly in [false, true] {
                for hasName in [false, true] {
                    let resolved = phase(
                        loadState: loadState,
                        processCount: 0,
                        visibleCount: 0,
                        hasActiveNameFilter: hasName,
                        risingOnly: risingOnly,
                        processListFailed: processListFailed
                    )
                    XCTAssertEqual(resolved, expected)
                    XCTAssertNil(MemoryTableEmptyCopy.filterEmptyLines(for: resolved))
                    XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: resolved))
                    XCTAssertNil(MemoryTableEmptyCopy.filterEmptyLines(for: resolved)?.buttonTitle)
                }
            }
        }
    }

    func testVisibleRowsStayReadyWithoutClearButton() {
        for risingOnly in [false, true] {
            for hasName in [false, true] {
                let resolved = phase(
                    loadState: .ready,
                    processCount: 4,
                    visibleCount: 2,
                    hasActiveNameFilter: hasName,
                    risingOnly: risingOnly
                )
                XCTAssertEqual(resolved, .ready)
                XCTAssertNil(MemoryTableEmptyCopy.filterEmptyLines(for: resolved))
                XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: resolved))
            }
        }
    }

    func testClearButtonLockWordIsAbsentOutsideFilterPhases() {
        let unresolved = phase(
            loadState: .ready,
            processCount: 4,
            visibleCount: 0,
            hasActiveNameFilter: false,
            risingOnly: false
        )
        XCTAssertEqual(unresolved, .empty)

        let phases: [MemoryTablePhase] = [
            .sampling,
            .processListFailed,
            .failed,
            .empty,
            unresolved,
            .ready,
        ]
        for phase in phases {
            XCTAssertNil(MemoryTableEmptyCopy.filterEmptyLines(for: phase), "\(phase)")
            XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: phase), "\(phase)")
            XCTAssertNotEqual(
                MemoryTableEmptyCopy.filterEmptyLines(for: phase)?.buttonTitle,
                "清空过滤"
            )
        }
        XCTAssertEqual(
            MemoryTableEmptyCopy.filterEmptyLines(for: .nameFilterEmpty)?.buttonTitle,
            "清空过滤"
        )
        XCTAssertEqual(
            MemoryTableEmptyCopy.filterEmptyLines(for: .risingOnlyEmpty)?.buttonTitle,
            "清空过滤"
        )
        XCTAssertNil(MemoryTableEmptyCopy.risingOnlyLines(for: .nameFilterEmpty))
        XCTAssertNotNil(MemoryTableEmptyCopy.risingOnlyLines(for: .risingOnlyEmpty))
    }

    func testClearWritesEmptyFilterAndRisingOffTogether() {
        let rows = [process(pid: 1, name: "Busy App", memory: 500)]
        let dirtyFilters = ["Zoom", "  NotARealApp  ", "没有这个", "   ", ""]
        for filter in dirtyFilters {
            let cleared = MemoryPageFilterClear.project(
                filter: filter,
                risingOnly: true,
                selectedPid: 1,
                rows: rows,
                page: .memory,
                seriesByPid: [:]
            )
            XCTAssertEqual(
                cleared,
                MemoryPageFilterClear(filter: "", risingOnly: false, selectedPid: 1),
                "dirty filter \(filter.debugDescription) clears both inputs on one beat"
            )
        }
    }

    func testClearKeepsNilSelection() {
        let rows = [process(pid: 1, name: "Busy App", memory: 500)]
        let cleared = MemoryPageFilterClear.project(
            filter: "Busy",
            risingOnly: true,
            selectedPid: nil,
            rows: rows,
            page: .memory,
            seriesByPid: [1: risingSeries()]
        )
        XCTAssertEqual(
            cleared,
            MemoryPageFilterClear(filter: "", risingOnly: false, selectedPid: nil)
        )
    }

    func testClearKeepsExistingPidWithoutConsultingBadge() {
        let rows = [process(pid: 9, name: "Quiet", memory: 80)]
        let seriesByPid = [Int32(1): risingSeries()]
        let cleared = MemoryPageFilterClear.project(
            filter: "zzz",
            risingOnly: true,
            selectedPid: 9,
            rows: rows,
            page: .memory,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(cleared.filter, "")
        XCTAssertFalse(cleared.risingOnly)
        XCTAssertEqual(cleared.selectedPid, 9)
        XCTAssertNotEqual(cleared.selectedPid, 1)
        XCTAssertNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 9, seriesByPid: seriesByPid),
            "kept pid has no list badge; OFF identity does not read it"
        )
    }

    func testClearDoesNotResurrectAPidRisingOnAlreadyCleared() {
        let rows = [
            process(pid: 7, name: "Fell Out", memory: 80),
            process(pid: 1, name: "Busy App", memory: 500),
        ]
        let seriesByPid = [Int32(1): risingSeries()]
        let afterOn = MemoryGrowthRisingFilter.selectedPid(
            current: 7,
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertNil(afterOn)

        let cleared = MemoryPageFilterClear.project(
            filter: "Busy",
            risingOnly: true,
            selectedPid: afterOn,
            rows: rows,
            page: .memory,
            seriesByPid: seriesByPid
        )
        XCTAssertNil(cleared.selectedPid)
        XCTAssertNotEqual(cleared.selectedPid, 7)
        XCTAssertNotEqual(cleared.selectedPid, 1)
        XCTAssertEqual(cleared.filter, "")
        XCTAssertFalse(cleared.risingOnly)
    }

    func testClearKeepsASelectionHiddenOnlyByName() {
        let rows = [
            process(pid: 1, name: "Busy App", memory: 500),
            process(pid: 2, name: "Helper", memory: 300),
        ]
        let seriesByPid = [Int32(1): risingSeries()]
        let hiddenRising = MemoryGrowthRisingFilter.selectedPid(
            current: 1,
            rows: rows,
            nameQuery: "Nope",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(hiddenRising, 1)

        let clearedRising = MemoryPageFilterClear.project(
            filter: "Nope",
            risingOnly: true,
            selectedPid: hiddenRising,
            rows: rows,
            page: .memory,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(
            clearedRising,
            MemoryPageFilterClear(filter: "", risingOnly: false, selectedPid: 1)
        )

        let hiddenOff = MemoryGrowthRisingFilter.selectedPid(
            current: 2,
            rows: rows,
            nameQuery: "Nope",
            page: .memory,
            risingOnly: false,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(hiddenOff, 2)
        let clearedOff = MemoryPageFilterClear.project(
            filter: "Nope",
            risingOnly: false,
            selectedPid: hiddenOff,
            rows: rows,
            page: .memory,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(
            clearedOff,
            MemoryPageFilterClear(filter: "", risingOnly: false, selectedPid: 2)
        )
    }

    func testClearLeavesSortRowsAndDoesNotSample() {
        let rows = [
            process(pid: 2, name: "Helper", memory: 100),
            process(pid: 1, name: "Busy App", memory: 400),
        ]
        let sort = ProcessTableSort(column: .name, descending: false)
        let sortedBefore = sort.ordered(rows).map(\.pid)
        let seriesByPid = [Int32(1): risingSeries()]
        let rowsBefore = rows

        let cleared = MemoryPageFilterClear.project(
            filter: "Nope",
            risingOnly: true,
            selectedPid: 1,
            rows: rows,
            page: .memory,
            seriesByPid: seriesByPid
        )

        XCTAssertEqual(rows, rowsBefore)
        XCTAssertEqual(sort, ProcessTableSort(column: .name, descending: false))
        XCTAssertEqual(sort.ordered(rows).map(\.pid), sortedBefore)
        XCTAssertEqual(cleared.filter, "")
        XCTAssertFalse(cleared.risingOnly)

        let visible = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: cleared.filter,
            page: .memory,
            risingOnly: cleared.risingOnly,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(visible.map(\.pid), rows.map(\.pid))
        XCTAssertEqual(sort.ordered(visible).map(\.pid), sortedBefore)
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
