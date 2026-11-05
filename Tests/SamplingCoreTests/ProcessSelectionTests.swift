import XCTest
@testable import SamplingCore

/// Phase 11 step 1: select-if-present + focus stays selection-free.
/// The process list scroll target is the same present-pid contract.
final class ProcessSelectionTests: XCTestCase {
    func testFocusMemoryPageDoesNotChangeSelectedPid() {
        let rows = [
            process(pid: 7, name: "Safari"),
            process(pid: 11, name: "Finder"),
        ]
        var selectedPid: Int32? = 11

        for page in DashboardPage.allCases {
            var navigation = DashboardNavigation(page: MenuBarNavigation(selectedPage: page))
            navigation.focusMemoryPage()
            XCTAssertEqual(navigation.selectedPage, .memory)
            XCTAssertEqual(selectedPid, 11, "focusMemoryPage is page-only; it must not rewrite selectedPid")
        }

        var menuBar = MenuBarNavigation(selectedPage: .cpu)
        menuBar.focusMemoryPage()
        XCTAssertEqual(menuBar.selectedPage, .memory)
        XCTAssertEqual(selectedPid, 11)
        XCTAssertEqual(ProcessSelection.acceptedPid(11, in: rows), 11)
    }

    func testPresentPidIsAcceptedForSelection() {
        let rows = [
            process(pid: 7, name: "Safari"),
            process(pid: 11, name: "Finder"),
            process(pid: 42, name: "Xcode"),
        ]

        XCTAssertEqual(ProcessSelection.acceptedPid(42, in: rows), 42)
        XCTAssertEqual(ProcessSelection.applying(pid: 42, to: 7, in: rows), 42)
        XCTAssertEqual(ProcessSelection.applying(pid: 11, to: nil, in: rows), 11)
    }

    func testMissingPidIsNotWrittenAndKeepsCurrentSelection() {
        let rows = [
            process(pid: 7, name: "Safari"),
            process(pid: 11, name: "Finder"),
        ]

        XCTAssertNil(ProcessSelection.acceptedPid(99, in: rows))
        XCTAssertEqual(ProcessSelection.applying(pid: 99, to: 7, in: rows), 7)
        XCTAssertNil(ProcessSelection.applying(pid: 99, to: nil, in: rows))
    }

    func testEmptyRowsRefuseAnyPidWithoutCrashing() {
        let vanished: Int32 = 7

        XCTAssertNil(ProcessSelection.acceptedPid(vanished, in: []))
        XCTAssertNil(ProcessSelection.applying(pid: vanished, to: nil, in: []))
        XCTAssertEqual(ProcessSelection.applying(pid: vanished, to: vanished, in: []), vanished)
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: vanished, rows: []))
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: nil, rows: []))
    }

    func testProcessListFailureHasNoSelectableRowAndRefusesAStalePid() {
        let stale = process(pid: 7, name: "Safari")
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: 4_294_967_296,
            samplingFailed: false,
            rows: [stale],
            processListFailed: true
        )

        XCTAssertTrue(strip.processes.isEmpty)
        XCTAssertEqual(strip.processesEmptyCopy, MenuBarCopy.processesEmpty)

        let rows: [ProcessRow] = []
        XCTAssertNil(ProcessSelection.acceptedPid(stale.pid, in: rows))
        XCTAssertNil(ProcessSelection.applying(pid: stale.pid, to: nil, in: rows))
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: stale.pid, rows: rows))
    }

    func testScrollTargetIsThePresentSelectedPid() {
        let rows = [
            process(pid: 7, name: "Safari"),
            process(pid: 11, name: "Finder"),
        ]

        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: 11, rows: rows), 11)
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: 99, rows: rows))
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: nil, rows: rows))
    }

    func testSelectingAPresentPidExposesThatRowAsTheScrollTarget() {
        let rows = [
            process(pid: 7, name: "Safari"),
            process(pid: 11, name: "Finder"),
        ]
        let selected = ProcessSelection.applying(pid: 11, to: nil, in: rows)

        XCTAssertEqual(selected, 11)
        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: selected, rows: rows), 11)
    }

    func testRefusingAVanishedPidDoesNotCreateAScrollTargetForIt() {
        let rows = [process(pid: 7, name: "Safari")]
        let selected = ProcessSelection.applying(pid: 99, to: 7, in: rows)

        XCTAssertEqual(selected, 7)
        XCTAssertNotEqual(selected, 99)
        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: selected, rows: rows), 7)
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: 99, rows: rows))
    }

    private func process(pid: Int32, name: String) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 1_000_000,
            threadCount: 1
        )
    }
}
