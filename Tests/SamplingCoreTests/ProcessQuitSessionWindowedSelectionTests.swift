import XCTest
@testable import SamplingCore

final class ProcessQuitSessionWindowedSelectionTests: XCTestCase {
    func testWindowedOnlyClearsInRowsSubjectWithoutSettling() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A"), row(2, "B")]
        _ = try fail(1, rows: rows, store: &store)
        let before = try XCTUnwrap(store.record(for: 1))
        let cleared = ProcessQuitSession.windowedOnlySelection(
            nextListPid: nil,
            sidebarSubjectPid: 1,
            rows: rows,
            store: store
        )
        XCTAssertNil(cleared.listSelectedPid)
        XCTAssertNil(cleared.sidebarSubjectPid)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), before)
        XCTAssertEqual(before.presence, .inRows)
        XCTAssertEqual(before.opportunity, .open)
    }

    func testWindowedOnlyKeepsAnAbsentUnknownSubjectAndItsRecord() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A")]
        _ = try fail(1, rows: rows, store: &store)
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 1,
            sidebarSubjectPid: 1,
            currentLiveDetail: detail(1, "A"),
            observation: ProcessQuitSession.Observation(rows: [])
        )
        let before = try XCTUnwrap(store.record(for: 1))
        let kept = ProcessQuitSession.windowedOnlySelection(
            nextListPid: nil,
            sidebarSubjectPid: 1,
            rows: [],
            store: store
        )
        XCTAssertNil(kept.listSelectedPid)
        XCTAssertEqual(kept.sidebarSubjectPid, 1)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), before)
        XCTAssertEqual(before.presence, .absentAndUnknown)
        XCTAssertEqual(before.opportunity, .open)
    }

    @discardableResult
    private func fail(
        _ pid: Int32,
        rows: [ProcessRow],
        store: inout ProcessQuitOutcome
    ) throws -> ProcessQuitIssued {
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        store.complete(pid: pid, token: issued.token, result: .stillRunning)
        return issued
    }

    private func row(_ pid: Int32, _ name: String, memory: UInt64 = 1_000) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 1,
            memoryBytes: memory,
            threadCount: 2
        )
    }

    private func detail(
        _ pid: Int32,
        _ name: String,
        memory: UInt64 = 1_000,
        memoryPoints: Int = 1,
        cpuPoints: Int = 1
    ) -> ProcessDetail {
        ProcessDetail(
            row: row(pid, name, memory: memory),
            memorySeries: series(count: memoryPoints, valueBase: 10),
            cpuSeries: series(count: cpuPoints, valueBase: 80)
        )
    }

    private func series(count: Int, valueBase: Double) -> [ChartSample] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                value: valueBase + Double(index)
            )
        }
    }
}
