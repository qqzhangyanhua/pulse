import XCTest
@testable import SamplingCore

final class HostNetworkLoadTests: XCTestCase {
    func testFirstFrameIsNilAndKeepsTheReadingAsBaseline() {
        let reading = snapshot(
            at: 10,
            interfaces: [up("en0", inbound: 8_192, outbound: 4_096)]
        )
        let sample = HostNetworkLoad.advance(previous: nil, reading: reading)
        XCTAssertNil(sample.rates.inboundBytesPerSecond)
        XCTAssertNil(sample.rates.outboundBytesPerSecond)
        XCTAssertEqual(sample.baseline, reading)
    }

    func testTwoFrameDeltaYieldsPositiveRates() {
        let previous = snapshot(
            at: 0,
            interfaces: [up("en0", inbound: 0, outbound: 0)]
        )
        let current = snapshot(
            at: 1.5,
            interfaces: [up("en0", inbound: 1_500, outbound: 300)]
        )
        let rates = HostNetworkLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.inboundBytesPerSecond ?? -1, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(rates.outboundBytesPerSecond ?? -1, 200, accuracy: 0.000_001)
    }

    func testIdleDeltaIsRealZeroNotAPlaceholder() {
        let previous = snapshot(
            at: 0,
            interfaces: [up("en0", inbound: 4_096, outbound: 2_048)]
        )
        let current = snapshot(
            at: 1.5,
            interfaces: [up("en0", inbound: 4_096, outbound: 2_048)]
        )
        let rates = HostNetworkLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.inboundBytesPerSecond ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(rates.outboundBytesPerSecond ?? -1, 0, accuracy: 0.000_001)
    }

    func testTotalsIgnoreLoopbackAndDownIfaces() {
        let snap = snapshot(
            at: 0,
            interfaces: [
                up("en0", inbound: 100, outbound: 40),
                loopback("lo0", inbound: 9_000, outbound: 8_000),
                down("awdl0", inbound: 7_000, outbound: 6_000),
            ]
        )
        XCTAssertEqual(
            HostNetworkLoad.totals(of: snap),
            HostNetworkCounters(inboundBytes: 100, outboundBytes: 40)
        )
    }

    func testLoopbackAndDownInterfacesAreExcluded() {
        let previous = snapshot(
            at: 0,
            interfaces: [
                up("en0", inbound: 0, outbound: 0),
                loopback("lo0", inbound: 0, outbound: 0),
                down("awdl0", inbound: 0, outbound: 0),
            ]
        )
        let current = snapshot(
            at: 1,
            interfaces: [
                up("en0", inbound: 100, outbound: 40),
                loopback("lo0", inbound: 50_000, outbound: 50_000),
                down("awdl0", inbound: 80_000, outbound: 80_000),
            ]
        )
        let rates = HostNetworkLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.inboundBytesPerSecond ?? -1, 100, accuracy: 0.000_001)
        XCTAssertEqual(rates.outboundBytesPerSecond ?? -1, 40, accuracy: 0.000_001)
    }

    func testNewInterfaceDoesNotSpikeTheSum() {
        let previous = snapshot(
            at: 0,
            interfaces: [up("en0", inbound: 1_000, outbound: 200)]
        )
        let current = snapshot(
            at: 1,
            interfaces: [
                up("en0", inbound: 1_250, outbound: 260),
                up("utun0", inbound: 10_000_000, outbound: 8_000_000),
            ]
        )
        let rates = HostNetworkLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.inboundBytesPerSecond ?? -1, 250, accuracy: 0.000_001)
        XCTAssertEqual(rates.outboundBytesPerSecond ?? -1, 60, accuracy: 0.000_001)
    }

    func testInterfaceSetChangeWithNoCommonEligibleIfaceIsNil() {
        let previous = snapshot(
            at: 0,
            interfaces: [loopback("lo0", inbound: 10, outbound: 10)]
        )
        let current = snapshot(
            at: 1,
            interfaces: [
                loopback("lo0", inbound: 20, outbound: 20),
                up("en0", inbound: 9_000_000, outbound: 7_000_000),
            ]
        )
        let rates = HostNetworkLoad.rates(previous: previous, current: current)
        XCTAssertNil(rates.inboundBytesPerSecond)
        XCTAssertNil(rates.outboundBytesPerSecond)
    }

    func testWrapIsNilAndDoesNotReportZero() {
        let previous = snapshot(
            at: 1,
            interfaces: [up("en0", inbound: 100, outbound: 80)]
        )
        let wrapped = snapshot(
            at: 2,
            interfaces: [up("en0", inbound: 8, outbound: 90)]
        )
        let rates = HostNetworkLoad.rates(previous: previous, current: wrapped)
        XCTAssertNil(rates.inboundBytesPerSecond)
        XCTAssertNil(rates.outboundBytesPerSecond)
        XCTAssertNotEqual(rates.inboundBytesPerSecond, 0)
        XCTAssertNotEqual(rates.outboundBytesPerSecond, 0)
    }

    func testZeroOrNegativeWallClockIsNil() {
        let date = Date(timeIntervalSince1970: 5)
        let previous = HostNetworkSnapshot(
            interfaces: [up("en0", inbound: 0, outbound: 0)],
            capturedAt: date
        )
        let sameInstant = HostNetworkSnapshot(
            interfaces: [up("en0", inbound: 100, outbound: 100)],
            capturedAt: date
        )
        XCTAssertEqual(HostNetworkLoad.rates(previous: previous, current: sameInstant), .missing)

        let backwards = HostNetworkSnapshot(
            interfaces: [up("en0", inbound: 100, outbound: 100)],
            capturedAt: Date(timeIntervalSince1970: 4)
        )
        XCTAssertEqual(HostNetworkLoad.rates(previous: previous, current: backwards), .missing)
    }

    func testFailedReadStaysNilAndKeepsBaseline() {
        let baseline = snapshot(
            at: 3,
            interfaces: [up("en0", inbound: 1_000, outbound: 200)]
        )
        let failed = HostNetworkLoad.advance(previous: baseline, reading: nil)
        XCTAssertEqual(failed.rates, .missing)
        XCTAssertEqual(failed.baseline, baseline)

        let next = snapshot(
            at: 4.5,
            interfaces: [up("en0", inbound: 2_500, outbound: 500)]
        )
        let recovered = HostNetworkLoad.advance(previous: failed.baseline, reading: next)
        XCTAssertEqual(recovered.rates.inboundBytesPerSecond ?? -1, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(recovered.rates.outboundBytesPerSecond ?? -1, 200, accuracy: 0.000_001)
        XCTAssertEqual(recovered.baseline, next)
    }

    func testWrapAdvancesBaselineSoTheNextFrameCanRecover() {
        let previous = snapshot(
            at: 1,
            interfaces: [up("en0", inbound: 100, outbound: 50)]
        )
        let wrapped = snapshot(
            at: 2,
            interfaces: [up("en0", inbound: 1, outbound: 2)]
        )
        let first = HostNetworkLoad.advance(previous: previous, reading: wrapped)
        XCTAssertEqual(first.rates, .missing)
        XCTAssertEqual(first.baseline, wrapped)

        let later = snapshot(
            at: 3,
            interfaces: [up("en0", inbound: 501, outbound: 202)]
        )
        let second = HostNetworkLoad.advance(previous: first.baseline, reading: later)
        XCTAssertEqual(second.rates.inboundBytesPerSecond ?? -1, 500, accuracy: 0.000_001)
        XCTAssertEqual(second.rates.outboundBytesPerSecond ?? -1, 200, accuracy: 0.000_001)
    }

    func testMultipleEligibleIfacesSumPerIfaceDeltas() {
        let previous = snapshot(
            at: 0,
            interfaces: [
                up("en0", inbound: 100, outbound: 10),
                up("en1", inbound: 200, outbound: 20),
            ]
        )
        let current = snapshot(
            at: 2,
            interfaces: [
                up("en0", inbound: 300, outbound: 50),
                up("en1", inbound: 600, outbound: 80),
            ]
        )
        let rates = HostNetworkLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.inboundBytesPerSecond ?? -1, 300, accuracy: 0.000_001)
        XCTAssertEqual(rates.outboundBytesPerSecond ?? -1, 50, accuracy: 0.000_001)
    }

    private func snapshot(
        at seconds: TimeInterval,
        interfaces: [HostNetworkInterfaceCounters]
    ) -> HostNetworkSnapshot {
        HostNetworkSnapshot(
            interfaces: interfaces,
            capturedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func up(_ name: String, inbound: UInt64, outbound: UInt64) -> HostNetworkInterfaceCounters {
        HostNetworkInterfaceCounters(
            name: name,
            inboundBytes: inbound,
            outboundBytes: outbound,
            isUp: true,
            isLoopback: false
        )
    }

    private func down(_ name: String, inbound: UInt64, outbound: UInt64) -> HostNetworkInterfaceCounters {
        HostNetworkInterfaceCounters(
            name: name,
            inboundBytes: inbound,
            outboundBytes: outbound,
            isUp: false,
            isLoopback: false
        )
    }

    private func loopback(_ name: String, inbound: UInt64, outbound: UInt64) -> HostNetworkInterfaceCounters {
        HostNetworkInterfaceCounters(
            name: name,
            inboundBytes: inbound,
            outboundBytes: outbound,
            isUp: true,
            isLoopback: true
        )
    }
}

final class SampledFrameNetworkTests: XCTestCase {
    func testFrameCarriesOptionalHostRates() {
        let missing = makeFrame(rates: .missing)
        XCTAssertNil(missing.hostNetworkRates.inboundBytesPerSecond)
        XCTAssertNil(missing.hostNetworkRates.outboundBytesPerSecond)

        let measured = makeFrame(
            rates: HostNetworkRates(inboundBytesPerSecond: 12.5, outboundBytesPerSecond: 4)
        )
        XCTAssertEqual(measured.hostNetworkRates.inboundBytesPerSecond ?? -1, 12.5, accuracy: 0.000_001)
        XCTAssertEqual(measured.hostNetworkRates.outboundBytesPerSecond ?? -1, 4, accuracy: 0.000_001)
    }

    func testProcessNetworkIsUnavailableAndNeverAByteCount() {
        let row = ProcessRow(
            pid: 7,
            name: "first-frame",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 3.2,
            memoryBytes: 1,
            threadCount: 1
        )
        XCTAssertEqual(row.networkAvailability, .unavailable)
        XCTAssertEqual(ProcessNetworkAvailability.unavailable.label, "暂不可用")

        let labels = Mirror(reflecting: row).children.compactMap(\.label)
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("network") })
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("byte") && $0.contains("net") })
    }

    func testProcessNetworkMarkerIsNotAZeroRate() {
        XCTAssertNotEqual(ProcessNetworkAvailability.unavailable.label, "0")
        XCTAssertNotEqual(ProcessNetworkAvailability.unavailable.label, "—")
        XCTAssertNotEqual(ProcessNetworkAvailability.unavailable.label, "0 B/s")
    }

    private func makeFrame(rates: HostNetworkRates) -> SampledFrame {
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
            systemCpuPercent: nil,
            hostNetworkRates: rates,
            hostDiskRates: .missing
        )
    }
}
