import XCTest
@testable import SamplingCore

/// Phase 21 pure annotation. Calls the real `HistoryCurvePresentation` and the
/// existing history rings. No copied enum, no `XCTFail` placeholder, no VM.
final class HistoryCurvePresentationTests: XCTestCase {
    func testUnavailableCopyIsTheLockedSentence() {
        XCTAssertEqual(HistoryCurvePresentation.unavailable, "历史曲线 · 当前值暂不可用")
    }

    func testAnnotationGateIsNilCurrentAndAtLeastTwoSamples() {
        XCTAssertNil(HistoryCurvePresentation.annotation(current: nil, sampleCount: 0))
        XCTAssertNil(HistoryCurvePresentation.annotation(current: nil, sampleCount: 1))
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: 2),
            HistoryCurvePresentation.unavailable
        )
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: 90),
            HistoryCurvePresentation.unavailable
        )
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 0, sampleCount: 2))
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 0, sampleCount: 90))
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 12.5, sampleCount: 2))
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 1, sampleCount: 0))
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 0, sampleCount: 1))
    }

    func testNilRecordOnEmptyCPURingDoesNotAnnotate() {
        var history = SystemCPUHistory()
        let before = history.samples.map(\.value)
        history.record(percent: nil, at: date(1))
        XCTAssertEqual(history.samples.count, 0)
        XCTAssertEqual(history.samples.map(\.value), before)
        XCTAssertNil(HistoryCurvePresentation.annotation(current: nil, sampleCount: history.samples.count))
        XCTAssertEqual(history.samples.count, 0)
    }

    func testNilAfterOneCPUSampleDoesNotAnnotate() {
        var history = SystemCPUHistory()
        history.record(percent: 10, at: date(1))
        history.record(percent: nil, at: date(2))
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.map(\.value), [10])
        XCTAssertNil(HistoryCurvePresentation.annotation(current: nil, sampleCount: history.samples.count))
        XCTAssertEqual(history.samples.map(\.value), [10])
    }

    func testNilAfterTwoCPUSamplesAnnotatesWithoutShortening() {
        var history = SystemCPUHistory()
        history.record(percent: 10, at: date(1))
        history.record(percent: 20, at: date(2))
        let values = history.samples.map(\.value)
        history.record(percent: nil, at: date(3))
        XCTAssertEqual(history.samples.count, 2)
        XCTAssertEqual(history.samples.map(\.value), values)
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.samples.count),
            HistoryCurvePresentation.unavailable
        )
        XCTAssertEqual(history.samples.map(\.value), values)
    }

    func testNilAfterDefaultCPULimitStaysNinetyAndAnnotates() {
        var history = SystemCPUHistory()
        for index in 0..<90 {
            history.record(percent: Double(index + 1), at: date(TimeInterval(index + 1)))
        }
        XCTAssertEqual(history.samples.count, 90)
        let values = history.samples.map(\.value)
        history.record(percent: nil, at: date(91))
        XCTAssertEqual(history.samples.count, 90)
        XCTAssertEqual(history.samples.map(\.value), values)
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    func testZeroAndPositiveCPUSamplesStayUnannotated() {
        var history = SystemCPUHistory()
        history.record(percent: 0, at: date(1))
        history.record(percent: 4, at: date(2))
        XCTAssertGreaterThanOrEqual(history.samples.count, 2)
        XCTAssertEqual(history.samples.map(\.value), [0, 4])
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 0, sampleCount: history.samples.count))
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 4, sampleCount: history.samples.count))
        XCTAssertEqual(history.samples.map(\.value), [0, 4])
    }

    func testCPURecoverZeroThenPositiveClearsAndNilReturns() {
        var history = SystemCPUHistory()
        history.record(percent: 10, at: date(1))
        history.record(percent: 20, at: date(2))
        history.record(percent: nil, at: date(3))
        XCTAssertEqual(history.samples.count, 2)
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.samples.count),
            HistoryCurvePresentation.unavailable
        )

        history.record(percent: 0, at: date(4))
        XCTAssertEqual(history.samples.count, 3)
        XCTAssertEqual(history.samples.map(\.value), [10, 20, 0])
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 0, sampleCount: history.samples.count))

        history.record(percent: 7, at: date(5))
        XCTAssertEqual(history.samples.count, 4)
        XCTAssertEqual(history.samples.last?.value, 7)
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 7, sampleCount: history.samples.count))

        let count = history.samples.count
        let values = history.samples.map(\.value)
        history.record(percent: nil, at: date(6))
        XCTAssertEqual(history.samples.count, count)
        XCTAssertGreaterThanOrEqual(history.samples.count, 2)
        XCTAssertEqual(history.samples.map(\.value), values)
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    func testCPUSameDateDoesNotAppendAndNilKeepsCount() {
        var history = SystemCPUHistory()
        history.record(percent: 10, at: date(1))
        history.record(percent: 99, at: date(1))
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.last?.value, 10)
        let values = history.samples.map(\.value)
        XCTAssertNil(HistoryCurvePresentation.annotation(current: 99, sampleCount: history.samples.count))
        XCTAssertEqual(history.samples.map(\.value), values)

        history.record(percent: nil, at: date(1))
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.last?.value, 10)
        XCTAssertNil(HistoryCurvePresentation.annotation(current: nil, sampleCount: history.samples.count))
    }

    func testCPUNilDateDoesNotAppend() {
        var history = SystemCPUHistory()
        history.record(percent: 10, at: date(1))
        history.record(percent: 20, at: nil)
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.map(\.value), [10])
        history.record(percent: 30, at: nil)
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.map(\.value), [10])
    }

    func testCPUNinetyFirstDropsOldestAndNonNilStaysUnannotated() {
        var history = SystemCPUHistory()
        for index in 0..<91 {
            history.record(percent: Double(index + 1), at: date(TimeInterval(index + 1)))
        }
        XCTAssertEqual(history.samples.count, 90)
        XCTAssertEqual(history.samples.first?.value, 2)
        XCTAssertEqual(history.samples.last?.value, 91)
        XCTAssertNil(
            HistoryCurvePresentation.annotation(
                current: history.samples.last?.value,
                sampleCount: history.samples.count
            )
        )
        XCTAssertEqual(history.samples.count, 90)
        XCTAssertEqual(history.samples.first?.value, 2)
    }

    func testNetworkInboundNilOutboundZeroStayIndependent() {
        var history = seededNetwork()
        let inboundCount = history.inbound.samples.count
        let outboundValues = history.outbound.samples.map(\.value)
        history.record(rates: networkRates(inbound: nil, outbound: 0), at: date(3))
        XCTAssertEqual(history.inbound.samples.count, inboundCount)
        XCTAssertGreaterThanOrEqual(history.inbound.samples.count, 2)
        XCTAssertEqual(history.outbound.samples.count, outboundValues.count + 1)
        XCTAssertEqual(history.outbound.samples.map(\.value), outboundValues + [0])
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.inbound.samples.count),
            HistoryCurvePresentation.unavailable
        )
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 0, sampleCount: history.outbound.samples.count)
        )
    }

    func testNetworkInboundZeroOutboundNilOnlyAnnotatesOutbound() {
        var history = seededNetwork()
        let outboundCount = history.outbound.samples.count
        let inboundValues = history.inbound.samples.map(\.value)
        history.record(rates: networkRates(inbound: 0, outbound: nil), at: date(3))
        XCTAssertEqual(history.outbound.samples.count, outboundCount)
        XCTAssertGreaterThanOrEqual(history.outbound.samples.count, 2)
        XCTAssertEqual(history.inbound.samples.count, inboundValues.count + 1)
        XCTAssertEqual(history.inbound.samples.map(\.value), inboundValues + [0])
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 0, sampleCount: history.inbound.samples.count)
        )
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.outbound.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    func testNetworkInboundNilOutboundPositiveOnlyAnnotatesInbound() {
        var history = seededNetwork()
        let inboundCount = history.inbound.samples.count
        let outboundValues = history.outbound.samples.map(\.value)
        history.record(rates: networkRates(inbound: nil, outbound: 50), at: date(3))
        XCTAssertEqual(history.inbound.samples.count, inboundCount)
        XCTAssertEqual(history.outbound.samples.map(\.value), outboundValues + [50])
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.inbound.samples.count),
            HistoryCurvePresentation.unavailable
        )
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 50, sampleCount: history.outbound.samples.count)
        )
    }

    func testNetworkOutboundNilInboundPositiveOnlyAnnotatesOutbound() {
        var history = seededNetwork()
        let outboundCount = history.outbound.samples.count
        let inboundValues = history.inbound.samples.map(\.value)
        history.record(rates: networkRates(inbound: 50, outbound: nil), at: date(3))
        XCTAssertEqual(history.outbound.samples.count, outboundCount)
        XCTAssertEqual(history.inbound.samples.map(\.value), inboundValues + [50])
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 50, sampleCount: history.inbound.samples.count)
        )
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.outbound.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    func testNetworkInboundRecoversToZeroWhileOutboundAppends() {
        var history = seededNetwork()
        history.record(rates: networkRates(inbound: nil, outbound: 30), at: date(3))
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.inbound.samples.count),
            HistoryCurvePresentation.unavailable
        )
        let outboundValues = history.outbound.samples.map(\.value)
        let inboundCount = history.inbound.samples.count
        history.record(rates: networkRates(inbound: 0, outbound: 40), at: date(4))
        XCTAssertEqual(history.inbound.samples.count, inboundCount + 1)
        XCTAssertEqual(history.inbound.samples.last?.value, 0)
        XCTAssertEqual(history.outbound.samples.map(\.value), outboundValues + [40])
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 0, sampleCount: history.inbound.samples.count)
        )
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 40, sampleCount: history.outbound.samples.count)
        )
    }

    func testNetworkInboundRecoversToPositiveWhileOutboundNilStays() {
        var history = seededNetwork()
        history.record(rates: networkRates(inbound: nil, outbound: 30), at: date(3))
        let outboundCount = history.outbound.samples.count
        let outboundValues = history.outbound.samples.map(\.value)
        let inboundCount = history.inbound.samples.count
        history.record(rates: networkRates(inbound: 8, outbound: nil), at: date(4))
        XCTAssertEqual(history.inbound.samples.count, inboundCount + 1)
        XCTAssertEqual(history.inbound.samples.last?.value, 8)
        XCTAssertEqual(history.outbound.samples.count, outboundCount)
        XCTAssertEqual(history.outbound.samples.map(\.value), outboundValues)
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 8, sampleCount: history.inbound.samples.count)
        )
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.outbound.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    func testNetworkOutboundRecoversToZeroWhileInboundAppends() {
        var history = seededNetwork()
        history.record(rates: networkRates(inbound: 30, outbound: nil), at: date(3))
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.outbound.samples.count),
            HistoryCurvePresentation.unavailable
        )
        let inboundValues = history.inbound.samples.map(\.value)
        let outboundCount = history.outbound.samples.count
        history.record(rates: networkRates(inbound: 40, outbound: 0), at: date(4))
        XCTAssertEqual(history.outbound.samples.count, outboundCount + 1)
        XCTAssertEqual(history.outbound.samples.last?.value, 0)
        XCTAssertEqual(history.inbound.samples.map(\.value), inboundValues + [40])
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 0, sampleCount: history.outbound.samples.count)
        )
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 40, sampleCount: history.inbound.samples.count)
        )
    }

    func testNetworkOutboundRecoversToPositiveWhileInboundNilStays() {
        var history = seededNetwork()
        history.record(rates: networkRates(inbound: 30, outbound: nil), at: date(3))
        let inboundCount = history.inbound.samples.count
        let inboundValues = history.inbound.samples.map(\.value)
        let outboundCount = history.outbound.samples.count
        history.record(rates: networkRates(inbound: nil, outbound: 8), at: date(4))
        XCTAssertEqual(history.outbound.samples.count, outboundCount + 1)
        XCTAssertEqual(history.outbound.samples.last?.value, 8)
        XCTAssertEqual(history.inbound.samples.count, inboundCount)
        XCTAssertEqual(history.inbound.samples.map(\.value), inboundValues)
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 8, sampleCount: history.outbound.samples.count)
        )
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.inbound.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    func testDiskReadNilWriteZeroStayIndependent() {
        var history = seededDisk()
        let readCount = history.read.samples.count
        let writeValues = history.write.samples.map(\.value)
        history.record(rates: diskRates(read: nil, write: 0), at: date(3))
        XCTAssertEqual(history.read.samples.count, readCount)
        XCTAssertGreaterThanOrEqual(history.read.samples.count, 2)
        XCTAssertEqual(history.write.samples.map(\.value), writeValues + [0])
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.read.samples.count),
            HistoryCurvePresentation.unavailable
        )
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 0, sampleCount: history.write.samples.count)
        )
    }

    func testDiskReadZeroWriteNilOnlyAnnotatesWrite() {
        var history = seededDisk()
        let writeCount = history.write.samples.count
        let readValues = history.read.samples.map(\.value)
        history.record(rates: diskRates(read: 0, write: nil), at: date(3))
        XCTAssertEqual(history.write.samples.count, writeCount)
        XCTAssertGreaterThanOrEqual(history.write.samples.count, 2)
        XCTAssertEqual(history.read.samples.map(\.value), readValues + [0])
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 0, sampleCount: history.read.samples.count)
        )
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.write.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    func testDiskReadNilWritePositiveOnlyAnnotatesRead() {
        var history = seededDisk()
        let readCount = history.read.samples.count
        let writeValues = history.write.samples.map(\.value)
        history.record(rates: diskRates(read: nil, write: 50), at: date(3))
        XCTAssertEqual(history.read.samples.count, readCount)
        XCTAssertEqual(history.write.samples.map(\.value), writeValues + [50])
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.read.samples.count),
            HistoryCurvePresentation.unavailable
        )
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 50, sampleCount: history.write.samples.count)
        )
    }

    func testDiskWriteNilReadPositiveOnlyAnnotatesWrite() {
        var history = seededDisk()
        let writeCount = history.write.samples.count
        let readValues = history.read.samples.map(\.value)
        history.record(rates: diskRates(read: 50, write: nil), at: date(3))
        XCTAssertEqual(history.write.samples.count, writeCount)
        XCTAssertEqual(history.read.samples.map(\.value), readValues + [50])
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 50, sampleCount: history.read.samples.count)
        )
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.write.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    func testDiskReadRecoversToZeroWhileWriteAppends() {
        var history = seededDisk()
        history.record(rates: diskRates(read: nil, write: 30), at: date(3))
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.read.samples.count),
            HistoryCurvePresentation.unavailable
        )
        let writeValues = history.write.samples.map(\.value)
        let readCount = history.read.samples.count
        history.record(rates: diskRates(read: 0, write: 40), at: date(4))
        XCTAssertEqual(history.read.samples.count, readCount + 1)
        XCTAssertEqual(history.read.samples.last?.value, 0)
        XCTAssertEqual(history.write.samples.map(\.value), writeValues + [40])
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 0, sampleCount: history.read.samples.count)
        )
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 40, sampleCount: history.write.samples.count)
        )
    }

    func testDiskReadRecoversToPositiveWhileWriteNilStays() {
        var history = seededDisk()
        history.record(rates: diskRates(read: nil, write: 30), at: date(3))
        let writeCount = history.write.samples.count
        let writeValues = history.write.samples.map(\.value)
        let readCount = history.read.samples.count
        history.record(rates: diskRates(read: 8, write: nil), at: date(4))
        XCTAssertEqual(history.read.samples.count, readCount + 1)
        XCTAssertEqual(history.read.samples.last?.value, 8)
        XCTAssertEqual(history.write.samples.count, writeCount)
        XCTAssertEqual(history.write.samples.map(\.value), writeValues)
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 8, sampleCount: history.read.samples.count)
        )
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.write.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    func testDiskWriteRecoversToZeroWhileReadAppends() {
        var history = seededDisk()
        history.record(rates: diskRates(read: 30, write: nil), at: date(3))
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.write.samples.count),
            HistoryCurvePresentation.unavailable
        )
        let readValues = history.read.samples.map(\.value)
        let writeCount = history.write.samples.count
        history.record(rates: diskRates(read: 40, write: 0), at: date(4))
        XCTAssertEqual(history.write.samples.count, writeCount + 1)
        XCTAssertEqual(history.write.samples.last?.value, 0)
        XCTAssertEqual(history.read.samples.map(\.value), readValues + [40])
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 0, sampleCount: history.write.samples.count)
        )
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 40, sampleCount: history.read.samples.count)
        )
    }

    func testDiskWriteRecoversToPositiveWhileReadNilStays() {
        var history = seededDisk()
        history.record(rates: diskRates(read: 30, write: nil), at: date(3))
        let readCount = history.read.samples.count
        let readValues = history.read.samples.map(\.value)
        let writeCount = history.write.samples.count
        history.record(rates: diskRates(read: nil, write: 8), at: date(4))
        XCTAssertEqual(history.write.samples.count, writeCount + 1)
        XCTAssertEqual(history.write.samples.last?.value, 8)
        XCTAssertEqual(history.read.samples.count, readCount)
        XCTAssertEqual(history.read.samples.map(\.value), readValues)
        XCTAssertNil(
            HistoryCurvePresentation.annotation(current: 8, sampleCount: history.write.samples.count)
        )
        XCTAssertEqual(
            HistoryCurvePresentation.annotation(current: nil, sampleCount: history.read.samples.count),
            HistoryCurvePresentation.unavailable
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func networkRates(inbound: Double?, outbound: Double?) -> HostNetworkRates {
        HostNetworkRates(inboundBytesPerSecond: inbound, outboundBytesPerSecond: outbound)
    }

    private func diskRates(read: Double?, write: Double?) -> HostDiskRates {
        HostDiskRates(readBytesPerSecond: read, writeBytesPerSecond: write)
    }

    private func seededNetwork() -> SystemNetworkHistory {
        var history = SystemNetworkHistory()
        history.record(rates: networkRates(inbound: 10, outbound: 20), at: date(1))
        history.record(rates: networkRates(inbound: 11, outbound: 21), at: date(2))
        return history
    }

    private func seededDisk() -> SystemDiskHistory {
        var history = SystemDiskHistory()
        history.record(rates: diskRates(read: 10, write: 20), at: date(1))
        history.record(rates: diskRates(read: 11, write: 21), at: date(2))
        return history
    }
}
