import XCTest
@testable import SamplingCore

final class WindowedAppFilterTests: XCTestCase {
    func testToggleStaysOnTheMemoryPage() {
        XCTAssertEqual(WindowedAppChrome.toggleTitle, "仅窗口 App")
        XCTAssertTrue(WindowedAppChrome.showsToggle(page: .memory))
        for page in [DashboardPage.cpu, .network, .disk, .gpu, .machine] {
            XCTAssertFalse(WindowedAppChrome.showsToggle(page: page))
        }
    }

    func testOffDoesNotQueryWindowedPids() {
        let rows = [row(1, "Chrome"), row(2, "kernel_task")]
        var calls = 0
        let kept = WindowedAppFilter.apply(
            rows: rows,
            page: .memory,
            windowedOnly: false,
            windowedPids: {
                calls += 1
                return [1]
            }
        )
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(kept, rows)
    }

    func testOtherPageDoesNotQueryWindowedPids() {
        let rows = [row(1, "Chrome"), row(2, "kernel_task")]
        var calls = 0
        let kept = WindowedAppFilter.apply(
            rows: rows,
            page: .cpu,
            windowedOnly: true,
            windowedPids: {
                calls += 1
                return [1]
            }
        )
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(kept, rows)
    }

    func testOpenMemoryPageQueriesWindowedPidsOnce() {
        let rows = [row(1, "Chrome"), row(2, "kernel_task"), row(3, "Stats")]
        var calls = 0
        let kept = WindowedAppFilter.apply(
            rows: rows,
            page: .memory,
            windowedOnly: true,
            windowedPids: {
                calls += 1
                return [1, 3]
            }
        )
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(kept.map(\.pid), [1, 3])
    }

    func testOffAndOtherPagesKeepEveryRow() {
        let rows = [row(1, "Chrome"), row(2, "kernel_task")]
        XCTAssertEqual(
            WindowedAppFilter.apply(rows: rows, page: .memory, windowedOnly: false, windowedPids: { [1] }),
            rows
        )
        XCTAssertEqual(
            WindowedAppFilter.apply(rows: rows, page: .cpu, windowedOnly: true, windowedPids: { [1] }),
            rows
        )
    }

    func testOnKeepsOnlyWindowedPids() {
        let rows = [row(1, "Chrome"), row(2, "kernel_task"), row(3, "Stats")]
        let kept = WindowedAppFilter.apply(
            rows: rows,
            page: .memory,
            windowedOnly: true,
            windowedPids: { [1, 3] }
        )
        XCTAssertEqual(kept.map(\.pid), [1, 3])
    }

    func testClosedSelectionDoesNotQueryWindowedPids() {
        var calls = 0
        let pid = WindowedAppFilter.selectedPid(
            current: 2,
            page: .memory,
            windowedOnly: false,
            windowedPids: {
                calls += 1
                return [1]
            }
        )
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(pid, 2)
    }

    func testOtherPageSelectionDoesNotQueryWindowedPids() {
        var calls = 0
        let pid = WindowedAppFilter.selectedPid(
            current: 2,
            page: .cpu,
            windowedOnly: true,
            windowedPids: {
                calls += 1
                return [1]
            }
        )
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(pid, 2)
    }

    func testOpenMemorySelectionQueriesWindowedPidsOnce() {
        var calls = 0
        let hidden = WindowedAppFilter.selectedPid(
            current: 2,
            page: .memory,
            windowedOnly: true,
            windowedPids: {
                calls += 1
                return [1]
            }
        )
        XCTAssertEqual(calls, 1)
        XCTAssertNil(hidden)

        calls = 0
        let kept = WindowedAppFilter.selectedPid(
            current: 1,
            page: .memory,
            windowedOnly: true,
            windowedPids: {
                calls += 1
                return [1]
            }
        )
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(kept, 1)

        calls = 0
        let missing = WindowedAppFilter.selectedPid(
            current: nil,
            page: .memory,
            windowedOnly: true,
            windowedPids: {
                calls += 1
                return [1]
            }
        )
        XCTAssertEqual(calls, 1)
        XCTAssertNil(missing)
    }

    func testSelectionDropsAHiddenPidAndOffDoesNotRestore() {
        XCTAssertEqual(
            WindowedAppFilter.selectedPid(current: 2, page: .memory, windowedOnly: true, windowedPids: { [1] }),
            nil
        )
        XCTAssertEqual(
            WindowedAppFilter.selectedPid(current: 2, page: .memory, windowedOnly: false, windowedPids: { [1] }),
            2
        )
        XCTAssertEqual(
            WindowedAppFilter.selectedPid(current: 1, page: .memory, windowedOnly: true, windowedPids: { [1] }),
            1
        )
        XCTAssertNil(WindowedAppFilter.selectedPid(current: nil, page: .memory, windowedOnly: true, windowedPids: { [1] }))
    }

    func testWindowedEmptyUsesTheNameFilterCopy() {
        let phase = MemoryTablePhaseResolver.resolve(
            page: .memory,
            loadState: .ready,
            processCount: 3,
            visibleCount: 0,
            hasActiveNameFilter: false,
            risingOnly: true,
            processListFailed: false,
            windowedOnly: true
        )
        XCTAssertEqual(phase, .nameFilterEmpty)
        XCTAssertEqual(MemoryTableEmptyCopy.filterEmptyLines(for: phase)?.title, "没有匹配的 App")
        XCTAssertEqual(MemoryTableEmptyCopy.filterEmptyLines(for: phase)?.buttonTitle, "清空过滤")

        let rising = MemoryTablePhaseResolver.resolve(
            page: .memory,
            loadState: .ready,
            processCount: 3,
            visibleCount: 0,
            hasActiveNameFilter: false,
            risingOnly: true,
            processListFailed: false
        )
        XCTAssertEqual(rising, .risingOnlyEmpty)

        let otherPage = MemoryTablePhaseResolver.resolve(
            page: .cpu,
            loadState: .ready,
            processCount: 3,
            visibleCount: 0,
            hasActiveNameFilter: false,
            risingOnly: false,
            processListFailed: false,
            windowedOnly: true
        )
        XCTAssertEqual(otherPage, .empty)
    }

    func testClearTurnsTheWindowedSwitchOff() {
        let cleared = MemoryPageFilterClear.project(
            filter: "Chrome",
            risingOnly: true,
            windowedOnly: true,
            selectedPid: 4,
            rows: [row(4, "Chrome")],
            page: .memory,
            seriesByPid: [:]
        )
        XCTAssertEqual(cleared.filter, "")
        XCTAssertFalse(cleared.risingOnly)
        XCTAssertFalse(cleared.windowedOnly)
        XCTAssertEqual(cleared.selectedPid, 4)
    }

    func testMenuBarAndSamplerStayOnTheFullList() throws {
        let vm = try source("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(vm.contains("WindowedAppLookup.pids(in: next.rows)"))
        XCTAssertTrue(vm.contains("WindowedAppLookup.pids(in: rows)"))
        let core = try source("Pulse/Models/DashboardCore+Selection.swift")
        let visible = try functionBody(named: "visibleRows", in: core)
        XCTAssertTrue(visible.contains("WindowedAppFilter.apply"))
        XCTAssertTrue(visible.contains("let pids = windowedPids"))
        XCTAssertTrue(visible.contains("windowedPids: { pids }"))
        XCTAssertFalse(visible.contains("WindowedAppLookup"))
        let selection = try functionBody(named: "applyWindowedOnlySelection", in: core)
        XCTAssertTrue(selection.contains("WindowedAppFilter.selectedPid"))
        XCTAssertTrue(selection.contains("windowedPids: { pids }"))
        XCTAssertFalse(selection.contains("WindowedAppLookup"))
        let menu = try functionBody(named: "menuBarPopover", in: core)
        XCTAssertTrue(menu.contains("rows: rows"))
        XCTAssertFalse(menu.contains("WindowedAppFilter"))
        XCTAssertFalse(menu.contains("windowedOnlyFilter"))

        let sampler = try source("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("WindowedAppFilter"))
        XCTAssertFalse(sampler.contains("windowedOnly"))

        let dashboard = try source("Pulse/Views/MemoryDashboardView.swift")
        XCTAssertTrue(dashboard.contains("title: WindowedAppChrome.toggleTitle,"))
        XCTAssertTrue(dashboard.contains(".help(WindowedAppChrome.help)"))
        let windowedAt = try XCTUnwrap(dashboard.range(of: "WindowedAppChrome.toggleTitle"))
        let risingAt = try XCTUnwrap(dashboard.range(of: "MemoryRisingOnlyChrome.toggleTitle"))
        XCTAssertLessThan(windowedAt.lowerBound, risingAt.lowerBound)
    }

    private func row(_ pid: Int32, _ name: String) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 10,
            threadCount: 1
        )
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        guard let range = source.range(of: "var \(name):") ?? source.range(of: "func \(name)("),
              let brace = source[range.lowerBound...].firstIndex(of: "{")
        else {
            XCTFail("missing \(name)")
            return ""
        }
        var depth = 0
        var index = brace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[brace...index])
                }
            }
            index = source.index(after: index)
        }
        return ""
    }
}
