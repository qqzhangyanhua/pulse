import XCTest
@testable import SamplingCore

final class MenuBarPopoverSnapshotTests: XCTestCase {
    func testNormalPressureLineReusesTitleAndCaption() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            samplingFailed: false,
            rows: [],
            processListFailed: false
        )
        XCTAssertEqual(strip.pressure, .normal)
        XCTAssertEqual(strip.pressureLine, "正常 · 余量充足")
        XCTAssertEqual(
            strip.pressureLine,
            MenuBarPopoverSnapshot.pressureLine(for: .normal)
        )
        XCTAssertEqual(PressureLevel.normal.title, "正常")
        XCTAssertEqual(PressureLevel.normal.caption, "余量充足")
        XCTAssertFalse(strip.pressureLine.contains("%"))
        XCTAssertFalse(strip.pressureLine.contains("0"))
    }

    func testElevatedPressureLineReusesTitleAndCaption() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .elevated,
            samplingFailed: false,
            rows: [],
            processListFailed: false
        )
        XCTAssertEqual(strip.pressure, .elevated)
        XCTAssertEqual(strip.pressureLine, "偏高 · 余量紧张")
        XCTAssertEqual(
            strip.pressureLine,
            MenuBarPopoverSnapshot.pressureLine(for: .elevated)
        )
        XCTAssertEqual(PressureLevel.elevated.title, "偏高")
        XCTAssertEqual(PressureLevel.elevated.caption, "余量紧张")
        XCTAssertFalse(strip.pressureLine.contains("%"))
    }

    func testMissingSnapshotIsTemporarilyUnreadableAndNeverFakeNormal() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: nil,
            samplingFailed: false,
            rows: [],
            processListFailed: false
        )
        XCTAssertEqual(strip, .empty)
        XCTAssertNil(strip.pressure)
        XCTAssertEqual(strip.pressureLine, MenuBarCopy.unavailableTooltip)
        XCTAssertEqual(strip.pressureLine, "暂时读不到")
        XCTAssertFalse(strip.pressureLine.contains("正常"))
        XCTAssertFalse(strip.pressureLine.contains("偏高"))
    }

    func testSamplingFailureHidesStalePressureAndNeverWritesZeroPercent() {
        let staleNormal = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            samplingFailed: true,
            rows: [process(pid: 11, name: "Safari", memory: 400_000_000)],
            processListFailed: false
        )
        let staleElevated = MenuBarPopoverSnapshot.project(
            pressure: .elevated,
            samplingFailed: true,
            rows: [],
            processListFailed: false
        )
        XCTAssertNil(staleNormal.pressure)
        XCTAssertNil(staleElevated.pressure)
        XCTAssertEqual(staleNormal.pressureLine, "暂时读不到")
        XCTAssertEqual(staleElevated.pressureLine, MenuBarPopoverShell.placeholder(for: .hostPressure))
        XCTAssertFalse(staleNormal.pressureLine.contains("正常"))
        XCTAssertFalse(staleElevated.pressureLine.contains("偏高"))
        XCTAssertFalse(staleNormal.pressureLine.contains("0%"))
        XCTAssertEqual(staleNormal.processes.map(\.name), ["Safari"])
    }

    func testTopProcessesTakeAtMostThreeByMemoryDescending() {
        let rows = [
            process(pid: 4, name: "tiny", memory: 10),
            process(pid: 1, name: "chrome", memory: 800),
            process(pid: 3, name: "mail", memory: 200),
            process(pid: 2, name: "xcode", memory: 500),
            process(pid: 5, name: "notes", memory: 50),
        ]
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            samplingFailed: false,
            rows: rows,
            processListFailed: false
        )
        XCTAssertEqual(MenuBarPopoverShell.maxProcessRows, 3)
        XCTAssertEqual(strip.processes.count, 3)
        XCTAssertEqual(strip.processes.map(\.name), ["chrome", "xcode", "mail"])
        XCTAssertEqual(strip.processes.map(\.memoryBytes), [800, 500, 200])
        XCTAssertEqual(strip.processes.map(\.pid), [1, 2, 3])
        XCTAssertNil(strip.processesEmptyCopy)
    }

    func testFewerThanThreeRowsAreShownWithoutPadding() {
        let one = MenuBarPopoverSnapshot.project(
            pressure: .elevated,
            samplingFailed: false,
            rows: [process(pid: 9, name: "only", memory: 42)],
            processListFailed: false
        )
        XCTAssertEqual(one.processes.count, 1)
        XCTAssertEqual(one.processes[0].name, "only")
        XCTAssertEqual(one.processes[0].memoryBytes, 42)
        XCTAssertNil(one.processesEmptyCopy)

        let two = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            samplingFailed: false,
            rows: [
                process(pid: 2, name: "low", memory: 1),
                process(pid: 1, name: "high", memory: 9),
            ],
            processListFailed: false
        )
        XCTAssertEqual(two.processes.map(\.name), ["high", "low"])
        XCTAssertEqual(two.processes.count, 2)
        XCTAssertNil(two.processesEmptyCopy)
    }

    func testEmptyRowsStayCalmAndNeverInventAZeroByteProcess() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            samplingFailed: false,
            rows: [],
            processListFailed: false
        )
        XCTAssertTrue(strip.processes.isEmpty)
        XCTAssertEqual(strip.processesEmptyCopy, "暂无进程")
        XCTAssertEqual(
            strip.processesEmptyCopy,
            MenuBarPopoverShell.placeholder(for: .topProcesses)
        )
        XCTAssertFalse(strip.processes.contains { $0.memoryBytes == 0 })
        XCTAssertFalse((strip.processesEmptyCopy ?? "").contains("0"))
        XCTAssertFalse((strip.processesEmptyCopy ?? "").contains("MB"))
    }

    func testProcessListFailureDropsExistingRowsInsteadOfFakingZero() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            samplingFailed: false,
            rows: [
                process(pid: 1, name: "stale", memory: 1_000),
                process(pid: 2, name: "also", memory: 2_000),
            ],
            processListFailed: true
        )
        XCTAssertTrue(strip.processes.isEmpty)
        XCTAssertEqual(strip.processesEmptyCopy, MenuBarCopy.processesEmpty)
        XCTAssertFalse(strip.processes.contains { $0.memoryBytes == 0 })
        XCTAssertEqual(strip.pressure, .normal)
        XCTAssertEqual(strip.pressureLine, "正常 · 余量充足")
    }

    func testARealZeroByteProcessIsKeptBecauseItIsNotAPlaceholder() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            samplingFailed: false,
            rows: [process(pid: 8, name: "idle", memory: 0)],
            processListFailed: false
        )
        XCTAssertEqual(strip.processes.count, 1)
        XCTAssertEqual(strip.processes[0].name, "idle")
        XCTAssertEqual(strip.processes[0].memoryBytes, 0)
        XCTAssertNil(strip.processesEmptyCopy)
    }

    func testEqualMemoryBreaksTiesByPidAscending() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            samplingFailed: false,
            rows: [
                process(pid: 30, name: "c", memory: 100),
                process(pid: 10, name: "a", memory: 100),
                process(pid: 20, name: "b", memory: 100),
                process(pid: 40, name: "drop", memory: 100),
            ],
            processListFailed: false
        )
        XCTAssertEqual(strip.processes.map(\.pid), [10, 20, 30])
        XCTAssertEqual(strip.processes.map(\.name), ["a", "b", "c"])
    }

    func testProjectionReadsTheFullRowListNotACallerFilter() {
        let unfiltered = [
            process(pid: 1, name: "keep-me", memory: 300),
            process(pid: 2, name: "other", memory: 100),
        ]
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            samplingFailed: false,
            rows: unfiltered,
            processListFailed: false
        )
        XCTAssertEqual(strip.processes.map(\.name), ["keep-me", "other"])
    }

    func testStripCopyNeverScaresOrMentionsKill() {
        let cases = [
            MenuBarPopoverSnapshot.project(
                pressure: .normal,
                samplingFailed: false,
                rows: [process(pid: 1, name: "Finder", memory: 12)],
                processListFailed: false
            ),
            MenuBarPopoverSnapshot.project(
                pressure: .elevated,
                samplingFailed: false,
                rows: [],
                processListFailed: false
            ),
            MenuBarPopoverSnapshot.project(
                pressure: nil,
                samplingFailed: true,
                rows: [],
                processListFailed: true
            ),
        ]
        let blob = cases.flatMap { strip in
            [
                strip.pressureLine,
                strip.processesEmptyCopy ?? "",
                strip.processes.map(\.name).joined(separator: " "),
            ]
        }
        .joined(separator: "\n")
        + "\n"
        + MenuBarCopy.openPulseTitle
        + "\n"
        + MenuBarCopy.quitTitle

        for word in ["危急", "泄漏", "泄露", "危险", "告警", "需要完全磁盘访问"] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("leak"))
        XCTAssertFalse(MenuBarCopy.openPulseTitle.contains("结束"))
        XCTAssertFalse(MenuBarCopy.openPulseTitle.contains("立即处理"))
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
