import XCTest
@testable import SamplingCore

final class ProcessCPUPercentTests: XCTestCase {
    func testFirstFrameIsNil() {
        let tick = CPUTick(userTimeNs: 2_000_000, systemTimeNs: 1_000_000, date: Date(timeIntervalSince1970: 10))
        XCTAssertNil(ProcessCPUPercent.percent(previous: nil, current: tick))
    }

    func testSecondFrameUsesWallClockDelta() {
        let previous = CPUTick(userTimeNs: 0, systemTimeNs: 0, date: Date(timeIntervalSince1970: 0))
        let current = CPUTick(
            userTimeNs: 500_000_000,
            systemTimeNs: 250_000_000,
            date: Date(timeIntervalSince1970: 1.5)
        )
        let percent = ProcessCPUPercent.percent(previous: previous, current: current)
        XCTAssertEqual(percent ?? -1, 50, accuracy: 0.000_001)
    }

    func testMultiThreadLoadMayExceedOneCore() {
        let previous = CPUTick(userTimeNs: 0, systemTimeNs: 0, date: Date(timeIntervalSince1970: 0))
        let current = CPUTick(
            userTimeNs: 2_000_000_000,
            systemTimeNs: 1_000_000_000,
            date: Date(timeIntervalSince1970: 1.5)
        )
        let percent = ProcessCPUPercent.percent(previous: previous, current: current)
        XCTAssertEqual(percent ?? -1, 200, accuracy: 0.000_001)
    }

    func testCounterRegressionIsNil() {
        let previous = CPUTick(userTimeNs: 50, systemTimeNs: 10, date: Date(timeIntervalSince1970: 1))
        let current = CPUTick(userTimeNs: 40, systemTimeNs: 10, date: Date(timeIntervalSince1970: 2))
        XCTAssertNil(ProcessCPUPercent.percent(previous: previous, current: current))
    }

    func testZeroOrNegativeWallClockIsNil() {
        let date = Date(timeIntervalSince1970: 5)
        let previous = CPUTick(userTimeNs: 0, systemTimeNs: 0, date: date)
        let sameInstant = CPUTick(userTimeNs: 100, systemTimeNs: 100, date: date)
        XCTAssertNil(ProcessCPUPercent.percent(previous: previous, current: sameInstant))

        let backwards = CPUTick(userTimeNs: 100, systemTimeNs: 100, date: Date(timeIntervalSince1970: 4))
        XCTAssertNil(ProcessCPUPercent.percent(previous: previous, current: backwards))
    }
}

final class SystemCPULoadTests: XCTestCase {
    func testFirstFrameIsNil() {
        let reading = HostCPUTicks(user: 10, system: 5, idle: 80, nice: 5)
        let sample = SystemCPULoad.advance(previous: nil, reading: reading)
        XCTAssertNil(sample.percent)
        XCTAssertEqual(sample.baseline, reading)
    }

    func testBusyTicksIncludeUserSystemAndNice() {
        let previous = HostCPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let current = HostCPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        let percent = SystemCPULoad.percent(previous: previous, current: current)
        XCTAssertEqual(percent ?? -1, 75, accuracy: 0.000_001)
    }

    func testIdleDeltaIsRealZeroNotAPlaceholder() {
        let previous = HostCPUTicks(user: 10, system: 10, idle: 10, nice: 10)
        let current = HostCPUTicks(user: 10, system: 10, idle: 110, nice: 10)
        let percent = SystemCPULoad.percent(previous: previous, current: current)
        XCTAssertEqual(percent ?? -1, 0, accuracy: 0.000_001)
    }

    func testNoTickProgressIsNil() {
        let ticks = HostCPUTicks(user: 4, system: 4, idle: 4, nice: 4)
        XCTAssertNil(SystemCPULoad.percent(previous: ticks, current: ticks))
    }

    func testWrapIsNilAndDoesNotReportZero() {
        let previous = HostCPUTicks(user: 100, system: 0, idle: 0, nice: 0)
        let wrapped = HostCPUTicks(user: 1, system: 0, idle: 1, nice: 0)
        XCTAssertNil(SystemCPULoad.percent(previous: previous, current: wrapped))
    }

    func testFailedReadStaysNilAndKeepsBaseline() {
        let baseline = HostCPUTicks(user: 3, system: 1, idle: 9, nice: 0)
        let failed = SystemCPULoad.advance(previous: baseline, reading: nil)
        XCTAssertNil(failed.percent)
        XCTAssertEqual(failed.baseline, baseline)

        let next = HostCPUTicks(user: 13, system: 1, idle: 19, nice: 0)
        let recovered = SystemCPULoad.advance(previous: failed.baseline, reading: next)
        XCTAssertEqual(recovered.percent ?? -1, 50, accuracy: 0.000_001)
        XCTAssertEqual(recovered.baseline, next)
    }

    func testWrapAdvancesBaselineSoTheNextFrameCanRecover() {
        let previous = HostCPUTicks(user: 100, system: 0, idle: 0, nice: 0)
        let wrapped = HostCPUTicks(user: 1, system: 0, idle: 1, nice: 0)
        let first = SystemCPULoad.advance(previous: previous, reading: wrapped)
        XCTAssertNil(first.percent)
        XCTAssertEqual(first.baseline, wrapped)

        let later = HostCPUTicks(user: 2, system: 0, idle: 2, nice: 0)
        let second = SystemCPULoad.advance(previous: first.baseline, reading: later)
        XCTAssertEqual(second.percent ?? -1, 50, accuracy: 0.000_001)
    }
}

final class SampledFrameCPUTests: XCTestCase {
    func testFrameCarriesOptionalSystemCPU() {
        let missing = makeFrame(systemCpuPercent: nil)
        XCTAssertNil(missing.systemCpuPercent)

        let measured = makeFrame(systemCpuPercent: 12.5)
        XCTAssertEqual(measured.systemCpuPercent ?? -1, 12.5, accuracy: 0.000_001)
    }

    func testMissingProcessCPUSortsBelowRealValuesWithoutUsingZero() {
        let row = ProcessRow(
            pid: 7,
            name: "first-frame",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 1,
            threadCount: 1
        )
        XCTAssertNil(row.cpuPercent)
        XCTAssertEqual(row.cpuSortKey, -1)
        XCTAssertLessThan(row.cpuSortKey, 0)
    }

    private func makeFrame(systemCpuPercent: Double?) -> SampledFrame {
        let now = Date(timeIntervalSince1970: 0)
        let snapshot = MemorySnapshot(
            usedBytes: 1,
            totalBytes: 4,
            breakdown: MemoryBreakdown(
                appBytes: 1,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0
            ),
            pressure: .normal,
            pressureMetric: 0.25,
            pressureSeries: [],
            capturedAt: now
        )
        return SampledFrame(
            snapshot: snapshot,
            rows: [],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: systemCpuPercent,
            hostNetworkRates: .missing
        )
    }
}
