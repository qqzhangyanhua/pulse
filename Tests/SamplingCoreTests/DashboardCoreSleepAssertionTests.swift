import XCTest
@testable import SamplingCore

/// Sleep-assertion rows and the energy-card tap live on `DashboardCore`.
final class DashboardCoreSleepAssertionTests: XCTestCase {
    func testApplyStoresTheRowsAndReturnsNoEffects() {
        var core = DashboardCore(ownPid: 1)
        let rows = [
            SleepAssertionRow(
                id: "20#0",
                pid: 20,
                name: "caffeinate",
                typeText: "阻止显示器睡眠",
                durationText: "5 秒"
            ),
        ]

        XCTAssertEqual(core.apply(sleepAssertions: rows), [])
        XCTAssertEqual(core.sleepAssertions, rows)
    }

    func testTapSelectsAPidThatIsInTheTable() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row(20, "caffeinate", memory: 10)])

        let effects = core.selectSleepAssertion(pid: 20)

        XCTAssertEqual(core.selectedPid, 20)
        XCTAssertEqual(effects, [.forwardSelectedPid(20)])
    }

    func testTapOfAPidMissingFromTheTableClearsSelection() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row(20, "caffeinate", memory: 10)])
        _ = core.select(pid: 20)

        let effects = core.selectSleepAssertion(pid: 7)

        XCTAssertNil(core.selectedPid)
        XCTAssertEqual(effects, [.forwardSelectedPid(nil)])
    }

    private func accept(_ core: inout DashboardCore, rows: [ProcessRow]) {
        core.apply(
            result: Result<SampledFrame, SleepAssertionDeliveryError>.success(frame(rows: rows)),
            accepted: true,
            page: core.selectedPage
        )
    }

    private func frame(rows: [ProcessRow]) -> SampledFrame {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = MemorySnapshot(
            usedBytes: 8_000_000,
            totalBytes: 16_000_000,
            breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
            pressure: .normal,
            pressureMetric: 0.1,
            pressureSeries: [],
            capturedAt: capturedAt,
            swapUsedBytes: 0
        )
        return SampledFrame(
            snapshot: snapshot,
            rows: rows,
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 1,
            hostNetworkRates: .missing,
            hostDiskRates: .missing
        )
    }

    private func row(_ pid: Int32, _ name: String, memory: UInt64) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 1,
            memoryBytes: memory,
            threadCount: 1
        )
    }
}

private enum SleepAssertionDeliveryError: Error {
    case unavailable
}
