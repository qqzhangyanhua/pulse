import XCTest
@testable import SamplingCore

final class HostDiskLoadTests: XCTestCase {
    func testFirstFrameIsNilAndKeepsTheReadingAsBaseline() {
        let reading = snapshot(
            at: 10,
            drivers: [driver("disk0", read: 8_192, written: 4_096)]
        )
        let sample = HostDiskLoad.advance(previous: nil, reading: reading)
        XCTAssertNil(sample.rates.readBytesPerSecond)
        XCTAssertNil(sample.rates.writeBytesPerSecond)
        XCTAssertEqual(sample.baseline, reading)
    }

    func testTwoFrameDeltaYieldsPositiveRates() {
        let previous = snapshot(
            at: 0,
            drivers: [driver("disk0", read: 0, written: 0)]
        )
        let current = snapshot(
            at: 1.5,
            drivers: [driver("disk0", read: 1_500, written: 300)]
        )
        let rates = HostDiskLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.readBytesPerSecond ?? -1, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(rates.writeBytesPerSecond ?? -1, 200, accuracy: 0.000_001)
    }

    func testIdleDeltaIsRealZeroNotAPlaceholder() {
        let previous = snapshot(
            at: 0,
            drivers: [driver("disk0", read: 4_096, written: 2_048)]
        )
        let current = snapshot(
            at: 1.5,
            drivers: [driver("disk0", read: 4_096, written: 2_048)]
        )
        let rates = HostDiskLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.readBytesPerSecond ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(rates.writeBytesPerSecond ?? -1, 0, accuracy: 0.000_001)
    }

    func testEmptyDriverSetIsNilNotZero() {
        let previous = snapshot(at: 0, drivers: [])
        let current = snapshot(at: 1, drivers: [])
        let rates = HostDiskLoad.rates(previous: previous, current: current)
        XCTAssertNil(rates.readBytesPerSecond)
        XCTAssertNil(rates.writeBytesPerSecond)
        XCTAssertNotEqual(rates.readBytesPerSecond, 0)
        XCTAssertNotEqual(rates.writeBytesPerSecond, 0)
    }

    func testNewDriverDoesNotSpikeTheSum() {
        let previous = snapshot(
            at: 0,
            drivers: [driver("disk0", read: 1_000, written: 200)]
        )
        let current = snapshot(
            at: 1,
            drivers: [
                driver("disk0", read: 1_250, written: 260),
                driver("disk2", read: 10_000_000, written: 8_000_000),
            ]
        )
        let rates = HostDiskLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.readBytesPerSecond ?? -1, 250, accuracy: 0.000_001)
        XCTAssertEqual(rates.writeBytesPerSecond ?? -1, 60, accuracy: 0.000_001)
    }

    func testDriverSetChangeWithNoCommonDriverIsNil() {
        let previous = snapshot(
            at: 0,
            drivers: [driver("disk0", read: 10, written: 10)]
        )
        let current = snapshot(
            at: 1,
            drivers: [driver("disk2", read: 9_000_000, written: 7_000_000)]
        )
        let rates = HostDiskLoad.rates(previous: previous, current: current)
        XCTAssertNil(rates.readBytesPerSecond)
        XCTAssertNil(rates.writeBytesPerSecond)
    }

    func testWrapIsNilAndDoesNotReportZero() {
        let previous = snapshot(
            at: 1,
            drivers: [driver("disk0", read: 100, written: 80)]
        )
        let wrapped = snapshot(
            at: 2,
            drivers: [driver("disk0", read: 8, written: 90)]
        )
        let rates = HostDiskLoad.rates(previous: previous, current: wrapped)
        XCTAssertNil(rates.readBytesPerSecond)
        XCTAssertNil(rates.writeBytesPerSecond)
        XCTAssertNotEqual(rates.readBytesPerSecond, 0)
        XCTAssertNotEqual(rates.writeBytesPerSecond, 0)
    }

    func testZeroOrNegativeWallClockIsNil() {
        let date = Date(timeIntervalSince1970: 5)
        let previous = HostDiskSnapshot(
            drivers: [driver("disk0", read: 0, written: 0)],
            capturedAt: date
        )
        let sameInstant = HostDiskSnapshot(
            drivers: [driver("disk0", read: 100, written: 100)],
            capturedAt: date
        )
        XCTAssertEqual(HostDiskLoad.rates(previous: previous, current: sameInstant), .missing)

        let backwards = HostDiskSnapshot(
            drivers: [driver("disk0", read: 100, written: 100)],
            capturedAt: Date(timeIntervalSince1970: 4)
        )
        XCTAssertEqual(HostDiskLoad.rates(previous: previous, current: backwards), .missing)
    }

    func testFailedReadStaysNilAndKeepsBaseline() {
        let baseline = snapshot(
            at: 3,
            drivers: [driver("disk0", read: 1_000, written: 200)]
        )
        let failed = HostDiskLoad.advance(previous: baseline, reading: nil)
        XCTAssertEqual(failed.rates, .missing)
        XCTAssertEqual(failed.baseline, baseline)

        let next = snapshot(
            at: 4.5,
            drivers: [driver("disk0", read: 2_500, written: 500)]
        )
        let recovered = HostDiskLoad.advance(previous: failed.baseline, reading: next)
        XCTAssertEqual(recovered.rates.readBytesPerSecond ?? -1, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(recovered.rates.writeBytesPerSecond ?? -1, 200, accuracy: 0.000_001)
        XCTAssertEqual(recovered.baseline, next)
    }

    func testWrapAdvancesBaselineSoTheNextFrameCanRecover() {
        let previous = snapshot(
            at: 1,
            drivers: [driver("disk0", read: 100, written: 50)]
        )
        let wrapped = snapshot(
            at: 2,
            drivers: [driver("disk0", read: 1, written: 2)]
        )
        let first = HostDiskLoad.advance(previous: previous, reading: wrapped)
        XCTAssertEqual(first.rates, .missing)
        XCTAssertEqual(first.baseline, wrapped)

        let later = snapshot(
            at: 3,
            drivers: [driver("disk0", read: 501, written: 202)]
        )
        let second = HostDiskLoad.advance(previous: first.baseline, reading: later)
        XCTAssertEqual(second.rates.readBytesPerSecond ?? -1, 500, accuracy: 0.000_001)
        XCTAssertEqual(second.rates.writeBytesPerSecond ?? -1, 200, accuracy: 0.000_001)
    }

    func testMultipleDriversSumPerDriverDeltas() {
        let previous = snapshot(
            at: 0,
            drivers: [
                driver("disk0", read: 100, written: 10),
                driver("disk1", read: 200, written: 20),
            ]
        )
        let current = snapshot(
            at: 2,
            drivers: [
                driver("disk0", read: 300, written: 50),
                driver("disk1", read: 600, written: 80),
            ]
        )
        let rates = HostDiskLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.readBytesPerSecond ?? -1, 300, accuracy: 0.000_001)
        XCTAssertEqual(rates.writeBytesPerSecond ?? -1, 50, accuracy: 0.000_001)
    }

    func testHostDiskCountersAreBlockDeviceBytesNotVMPageins() {
        let labels = Mirror(reflecting: HostDiskDriverCounters(id: "disk0", bytesRead: 1, bytesWritten: 2))
            .children
            .compactMap(\.label)
        XCTAssertEqual(Set(labels), ["id", "bytesRead", "bytesWritten"])
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("page") })
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("network") })
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("message") })
    }

    private func snapshot(
        at seconds: TimeInterval,
        drivers: [HostDiskDriverCounters]
    ) -> HostDiskSnapshot {
        HostDiskSnapshot(
            drivers: drivers,
            capturedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func driver(_ id: String, read: UInt64, written: UInt64) -> HostDiskDriverCounters {
        HostDiskDriverCounters(id: id, bytesRead: read, bytesWritten: written)
    }
}

final class ProcessDiskLoadTests: XCTestCase {
    func testFirstFrameIsNil() {
        let tick = DiskTick(bytesRead: 2_000, bytesWritten: 1_000, date: Date(timeIntervalSince1970: 10))
        let sample = ProcessDiskLoad.advance(previous: nil, reading: tick)
        XCTAssertNil(sample.rates.readBytesPerSecond)
        XCTAssertNil(sample.rates.writeBytesPerSecond)
        XCTAssertEqual(sample.baseline, tick)
    }

    func testTwoFrameDeltaYieldsPositiveRates() {
        let previous = DiskTick(bytesRead: 0, bytesWritten: 0, date: Date(timeIntervalSince1970: 0))
        let current = DiskTick(bytesRead: 1_500, bytesWritten: 300, date: Date(timeIntervalSince1970: 1.5))
        let rates = ProcessDiskLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.readBytesPerSecond ?? -1, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(rates.writeBytesPerSecond ?? -1, 200, accuracy: 0.000_001)
    }

    func testIdleDeltaIsRealZeroNotAPlaceholder() {
        let previous = DiskTick(bytesRead: 4_096, bytesWritten: 2_048, date: Date(timeIntervalSince1970: 0))
        let current = DiskTick(bytesRead: 4_096, bytesWritten: 2_048, date: Date(timeIntervalSince1970: 2))
        let rates = ProcessDiskLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.readBytesPerSecond ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(rates.writeBytesPerSecond ?? -1, 0, accuracy: 0.000_001)
    }

    func testEPERMOrFailedRusageIsNilAndKeepsBaseline() {
        let baseline = DiskTick(bytesRead: 1_000, bytesWritten: 200, date: Date(timeIntervalSince1970: 3))
        let denied = ProcessDiskLoad.advance(previous: baseline, reading: nil)
        XCTAssertEqual(denied.rates, .missing)
        XCTAssertEqual(denied.baseline, baseline)
        XCTAssertNotEqual(denied.rates.readBytesPerSecond, 0)
        XCTAssertNotEqual(denied.rates.writeBytesPerSecond, 0)

        let next = DiskTick(bytesRead: 2_500, bytesWritten: 500, date: Date(timeIntervalSince1970: 4.5))
        let recovered = ProcessDiskLoad.advance(previous: denied.baseline, reading: next)
        XCTAssertEqual(recovered.rates.readBytesPerSecond ?? -1, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(recovered.rates.writeBytesPerSecond ?? -1, 200, accuracy: 0.000_001)
    }

    func testWrapIsNilAndDoesNotReportZero() {
        let previous = DiskTick(bytesRead: 100, bytesWritten: 80, date: Date(timeIntervalSince1970: 1))
        let wrapped = DiskTick(bytesRead: 8, bytesWritten: 90, date: Date(timeIntervalSince1970: 2))
        let rates = ProcessDiskLoad.rates(previous: previous, current: wrapped)
        XCTAssertNil(rates.readBytesPerSecond)
        XCTAssertNil(rates.writeBytesPerSecond)
        XCTAssertNotEqual(rates.readBytesPerSecond, 0)
        XCTAssertNotEqual(rates.writeBytesPerSecond, 0)
    }

    func testZeroOrNegativeWallClockIsNil() {
        let date = Date(timeIntervalSince1970: 5)
        let previous = DiskTick(bytesRead: 0, bytesWritten: 0, date: date)
        let sameInstant = DiskTick(bytesRead: 100, bytesWritten: 100, date: date)
        XCTAssertEqual(ProcessDiskLoad.rates(previous: previous, current: sameInstant), .missing)

        let backwards = DiskTick(bytesRead: 100, bytesWritten: 100, date: Date(timeIntervalSince1970: 4))
        XCTAssertEqual(ProcessDiskLoad.rates(previous: previous, current: backwards), .missing)
    }

    func testWrapAdvancesBaselineSoTheNextFrameCanRecover() {
        let previous = DiskTick(bytesRead: 100, bytesWritten: 50, date: Date(timeIntervalSince1970: 1))
        let wrapped = DiskTick(bytesRead: 1, bytesWritten: 2, date: Date(timeIntervalSince1970: 2))
        let first = ProcessDiskLoad.advance(previous: previous, reading: wrapped)
        XCTAssertEqual(first.rates, .missing)
        XCTAssertEqual(first.baseline, wrapped)

        let later = DiskTick(bytesRead: 501, bytesWritten: 202, date: Date(timeIntervalSince1970: 3))
        let second = ProcessDiskLoad.advance(previous: first.baseline, reading: later)
        XCTAssertEqual(second.rates.readBytesPerSecond ?? -1, 500, accuracy: 0.000_001)
        XCTAssertEqual(second.rates.writeBytesPerSecond ?? -1, 200, accuracy: 0.000_001)
    }

    func testDiskTickIsRusageBytesNotMachPageins() {
        let labels = Mirror(reflecting: DiskTick(bytesRead: 1, bytesWritten: 2, date: Date(timeIntervalSince1970: 0)))
            .children
            .compactMap(\.label)
        XCTAssertEqual(Set(labels), ["bytesRead", "bytesWritten", "date"])
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("page") })
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("fault") })
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("message") })
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("network") })
    }
}

final class SampledFrameDiskTests: XCTestCase {
    func testFrameCarriesOptionalHostRates() {
        let missing = makeFrame(rates: .missing, rows: [])
        XCTAssertNil(missing.hostDiskRates.readBytesPerSecond)
        XCTAssertNil(missing.hostDiskRates.writeBytesPerSecond)

        let measured = makeFrame(
            rates: HostDiskRates(readBytesPerSecond: 12.5, writeBytesPerSecond: 4),
            rows: []
        )
        XCTAssertEqual(measured.hostDiskRates.readBytesPerSecond ?? -1, 12.5, accuracy: 0.000_001)
        XCTAssertEqual(measured.hostDiskRates.writeBytesPerSecond ?? -1, 4, accuracy: 0.000_001)
    }

    func testProcessDiskUnavailableIsNilRateNotAFabricatedZero() {
        let row = ProcessRow(
            pid: 7,
            name: "first-frame",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 3.2,
            memoryBytes: 1,
            threadCount: 1
        )
        XCTAssertNil(row.diskReadBytesPerSecond)
        XCTAssertNil(row.diskWriteBytesPerSecond)
        XCTAssertEqual(row.diskSortKey, -1)
        XCTAssertLessThan(row.diskSortKey, 0)
        XCTAssertNotEqual(row.diskSortKey, 0)
        XCTAssertEqual(row.networkAvailability, .unavailable)
    }

    func testProcessDiskRatesStayOnTheRowAndMissingSinks() {
        let missing = ProcessRow(
            pid: 1,
            name: "denied",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 1,
            threadCount: 1
        )
        let idle = ProcessRow(
            pid: 2,
            name: "idle",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 1,
            threadCount: 1,
            diskReadBytesPerSecond: 0,
            diskWriteBytesPerSecond: 0
        )
        let busy = ProcessRow(
            pid: 3,
            name: "busy",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 1,
            threadCount: 1,
            diskReadBytesPerSecond: 40,
            diskWriteBytesPerSecond: 10
        )
        XCTAssertEqual(busy.diskSortKey, 50)
        XCTAssertEqual(idle.diskSortKey, 0)
        XCTAssertEqual(missing.diskSortKey, -1)
        XCTAssertLessThan(missing.diskSortKey, idle.diskSortKey)
        XCTAssertLessThan(idle.diskSortKey, busy.diskSortKey)
    }

    func testProcessDiskIsNotTheNetworkUnavailableMarker() {
        let row = ProcessRow(
            pid: 11,
            name: "helper",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 4,
            memoryBytes: 8,
            threadCount: 2,
            diskReadBytesPerSecond: nil,
            diskWriteBytesPerSecond: nil
        )
        XCTAssertEqual(row.networkAvailability.label, "暂不可用")
        XCTAssertNil(row.diskReadBytesPerSecond)
        XCTAssertNil(row.diskWriteBytesPerSecond)
        XCTAssertNotEqual(String(describing: row.diskReadBytesPerSecond), "暂不可用")
    }

    private func makeFrame(rates: HostDiskRates, rows: [ProcessRow]) -> SampledFrame {
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
            rows: rows,
            detail: nil,
            processListFailed: false,
            systemCpuPercent: nil,
            hostNetworkRates: .missing,
            hostDiskRates: rates
        )
    }
}
