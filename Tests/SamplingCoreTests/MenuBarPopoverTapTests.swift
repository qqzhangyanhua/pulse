import XCTest
@testable import SamplingCore

/// Phase 11 step 2: Top3 tap wiring. Uses the step-1 select-if-present /
/// scroll-target contract; does not invent a second open / select API.
final class MenuBarPopoverTapTests: XCTestCase {
    func testTop3ProcessRowsAreTappableByPid() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: 4_294_967_296,
            samplingFailed: false,
            rows: [
                process(pid: 1, name: "chrome", memory: 800),
                process(pid: 2, name: "xcode", memory: 500),
                process(pid: 3, name: "mail", memory: 200),
                process(pid: 4, name: "notes", memory: 50),
            ],
            processListFailed: false
        )

        XCTAssertEqual(strip.processes.map(\.pid), [1, 2, 3])
        XCTAssertEqual(MenuBarPopoverTap.tappableProcessPids(in: strip), [1, 2, 3])
        XCTAssertEqual(
            MenuBarPopoverTap.targets(in: strip),
            [.process(1), .process(2), .process(3), .openPulse]
        )
    }

    func testEmptyAndProcessListFailedHaveNoTappableRows() {
        let empty = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: nil,
            samplingFailed: false,
            rows: [],
            processListFailed: false
        )
        let failed = MenuBarPopoverSnapshot.project(
            pressure: .elevated,
            usedBytes: 8_589_934_592,
            samplingFailed: false,
            rows: [process(pid: 7, name: "Safari", memory: 400_000_000)],
            processListFailed: true
        )

        XCTAssertTrue(empty.processes.isEmpty)
        XCTAssertEqual(empty.processesEmptyCopy, MenuBarCopy.processesEmpty)
        XCTAssertTrue(MenuBarPopoverTap.tappableProcessPids(in: empty).isEmpty)
        XCTAssertEqual(MenuBarPopoverTap.targets(in: empty), [.openPulse])

        XCTAssertTrue(failed.processes.isEmpty)
        XCTAssertEqual(failed.processesEmptyCopy, "暂无进程")
        XCTAssertTrue(MenuBarPopoverTap.tappableProcessPids(in: failed).isEmpty)
        XCTAssertEqual(MenuBarPopoverTap.targets(in: failed), [.openPulse])
    }

    func testPressureAndUsedMemoryAreNotTappableTargets() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .elevated,
            usedBytes: 13_261_991_936,
            samplingFailed: false,
            rows: [process(pid: 11, name: "Finder", memory: 12)],
            processListFailed: false
        )

        XCTAssertEqual(strip.hostBlockLines, [strip.pressureLine, strip.usedMemoryLine])
        XCTAssertEqual(strip.hostBlockLines.count, MenuBarPopoverShell.hostBlockLineCount)
        XCTAssertFalse(MenuBarPopoverTap.hostBlockIsTappable)
        XCTAssertFalse(
            MenuBarPopoverTap.targets(in: strip).contains { target in
                switch target {
                case .process, .openPulse:
                    return false
                }
            }
        )
        XCTAssertEqual(MenuBarPopoverTap.targets(in: strip), [.process(11), .openPulse])

        let busy = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: 13_261_991_936,
            samplingFailed: false,
            rows: [process(pid: 11, name: "Finder", memory: 12)],
            processListFailed: false,
            busiestCorePercent: 92
        )
        XCTAssertEqual(busy.busiestCoreLine, "最忙的一核 · 92.0%")
        XCTAssertEqual(busy.hostBlockLines.count, MenuBarPopoverShell.hostBlockLineCount + 1)
        XCTAssertFalse(MenuBarPopoverTap.hostBlockIsTappable)
        XCTAssertEqual(MenuBarPopoverTap.targets(in: busy), [.process(11), .openPulse])
    }

    func testProcessTapStepsAreDismissThenSelectIfPresentThenFocus() {
        XCTAssertEqual(
            MenuBarPopoverTap.steps(for: .process(42)),
            [.dismissPopover, .selectPidIfPresent(42), .focusMemoryPage]
        )
    }

    func testOpenPulseStepsAreDismissThenFocusWithoutChangingSelection() {
        XCTAssertEqual(
            MenuBarPopoverTap.steps(for: .openPulse),
            [.dismissPopover, .focusMemoryPage]
        )
        XCTAssertFalse(
            MenuBarPopoverTap.steps(for: .openPulse).contains { step in
                if case .selectPidIfPresent = step { return true }
                return false
            }
        )
    }

    func testApplyingAPresentPidTapSelectsItAndExposesTheScrollTarget() {
        let rows = [
            process(pid: 7, name: "Safari", memory: 100),
            process(pid: 11, name: "Finder", memory: 200),
        ]
        var selectedPid: Int32? = 7
        var focused = false

        apply(MenuBarPopoverTap.steps(for: .process(11)), selectedPid: &selectedPid, rows: rows) {
            focused = true
        }

        XCTAssertEqual(selectedPid, 11)
        XCTAssertTrue(focused)
        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows), 11)
    }

    func testApplyingAVanishedPidTapDoesNotWriteAGhostSelection() {
        let rows = [process(pid: 7, name: "Safari", memory: 100)]
        var selectedPid: Int32? = 7
        var focused = false

        apply(MenuBarPopoverTap.steps(for: .process(99)), selectedPid: &selectedPid, rows: rows) {
            focused = true
        }

        XCTAssertEqual(selectedPid, 7)
        XCTAssertNotEqual(selectedPid, 99)
        XCTAssertTrue(focused)
        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows), 7)
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: 99, rows: rows))
    }

    func testOpenPulseKeepsTheCurrentSelectionAndStillFocuses() {
        let rows = [
            process(pid: 7, name: "Safari", memory: 100),
            process(pid: 11, name: "Finder", memory: 200),
        ]
        var selectedPid: Int32? = 11
        var focused = false

        apply(MenuBarPopoverTap.steps(for: .openPulse), selectedPid: &selectedPid, rows: rows) {
            focused = true
        }

        XCTAssertEqual(selectedPid, 11)
        XCTAssertTrue(focused)
        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows), 11)

        selectedPid = nil
        apply(MenuBarPopoverTap.steps(for: .openPulse), selectedPid: &selectedPid, rows: rows) {
            focused = true
        }
        XCTAssertNil(selectedPid)
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows))
    }

    func testProcessListScrollTargetStaysTheStepOnePresentPidContract() {
        let rows = [
            process(pid: 7, name: "Safari", memory: 100),
            process(pid: 11, name: "Finder", memory: 200),
        ]
        let selected = ProcessSelection.applying(pid: 11, to: nil, in: rows)

        XCTAssertEqual(selected, 11)
        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: selected, rows: rows), 11)
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: 99, rows: rows))
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: nil, rows: rows))
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: 7, rows: []))
    }

    func testTapCopyNeverScaresOrMentionsKill() {
        let blob = [
            MenuBarCopy.openPulseTitle,
            MenuBarCopy.processesEmpty,
            MenuBarCopy.unavailableTooltip,
        ].joined(separator: "\n")

        for word in ["危急", "泄漏", "泄露", "危险", "告警", "结束", "强制退出"] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("leak"))
        XCTAssertEqual(MenuBarCopy.openPulseTitle, "打开 Pulse")
    }

    private func apply(
        _ steps: [MenuBarPopoverTapStep],
        selectedPid: inout Int32?,
        rows: [ProcessRow],
        onFocus: () -> Void
    ) {
        for step in steps {
            switch step {
            case .dismissPopover:
                continue
            case .selectPidIfPresent(let pid):
                selectedPid = ProcessSelection.applying(pid: pid, to: selectedPid, in: rows)
            case .focusMemoryPage:
                onFocus()
            }
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
