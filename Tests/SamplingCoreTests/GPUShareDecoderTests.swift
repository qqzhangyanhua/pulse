import XCTest
@testable import SamplingCore

/// AGX user-client properties in, per-pid GPU share out. No IOKit.
final class GPUShareDecoderTests: XCTestCase {
    func testTwoFramesDivideGPUTimeByWallClock() {
        let previous = GPUShareDecoder.parse(id: 1, properties: client(pid: 10, name: "Safari", times: [1_000_000_000]))
        let current = GPUShareDecoder.parse(id: 1, properties: client(pid: 10, name: "Safari", times: [1_500_000_000]))
        let readings = GPUShareDecoder.shares(
            previous: [previous],
            current: [current],
            elapsedNanoseconds: 2_000_000_000
        )

        XCTAssertEqual(readings.map(\.pid), [10])
        XCTAssertEqual(readings[0].percent, 25)
        XCTAssertEqual(readings[0].text, "25.0%")
    }

    func testClientsAndAppUsageEntriesSumBeforeTheDelta() {
        let previous = [
            GPUShareDecoder.parse(id: 1, properties: client(pid: 10, name: "Safari", times: [100_000_000, 200_000_000])),
            GPUShareDecoder.parse(id: 2, properties: client(pid: 10, name: "Safari", times: [700_000_000])),
        ]
        let current = [
            GPUShareDecoder.parse(id: 1, properties: client(pid: 10, name: "Safari", times: [400_000_000, 200_000_000])),
            GPUShareDecoder.parse(id: 2, properties: client(pid: 10, name: "Safari", times: [900_000_000])),
        ]
        let readings = GPUShareDecoder.shares(
            previous: previous,
            current: current,
            elapsedNanoseconds: 1_000_000_000
        )

        XCTAssertEqual(readings.map(\.pid), [10])
        XCTAssertEqual(readings[0].percent, 50)
        XCTAssertEqual(readings[0].text, "50.0%")
    }

    func testShareAboveOneHundredIsKept() {
        let readings = GPUShareDecoder.shares(
            previous: [GPUShareDecoder.parse(id: 1, properties: client(pid: 4, name: "FinalCut", times: [0]))],
            current: [GPUShareDecoder.parse(id: 1, properties: client(pid: 4, name: "FinalCut", times: [2_500_000_000]))],
            elapsedNanoseconds: 1_000_000_000
        )

        XCTAssertEqual(readings.map(\.pid), [4])
        XCTAssertEqual(readings[0].percent, 250)
        XCTAssertEqual(readings[0].text, "250.0%")
    }

    func testCounterRewindIsMissingNotZero() {
        let readings = GPUShareDecoder.shares(
            previous: [GPUShareDecoder.parse(id: 1, properties: client(pid: 8, name: "Preview", times: [2_000_000_000]))],
            current: [GPUShareDecoder.parse(id: 1, properties: client(pid: 8, name: "Preview", times: [1_000_000_000]))],
            elapsedNanoseconds: 1_000_000_000
        )

        XCTAssertEqual(readings.map(\.pid), [8])
        XCTAssertNil(readings[0].percent)
        XCTAssertEqual(readings[0].text, "—")
        XCTAssertNotEqual(readings[0].text, "0.0%")
    }

    func testDisappearedClientIsMissingNotTheRemainingDelta() {
        let previous = [
            GPUShareDecoder.parse(id: 1, properties: client(pid: 10, name: "Safari", times: [1_000_000_000])),
            GPUShareDecoder.parse(id: 2, properties: client(pid: 10, name: "Safari", times: [1_000_000_000])),
        ]
        let current = [
            GPUShareDecoder.parse(id: 1, properties: client(pid: 10, name: "Safari", times: [2_000_000_000])),
        ]
        let readings = GPUShareDecoder.shares(
            previous: previous,
            current: current,
            elapsedNanoseconds: 1_000_000_000
        )

        XCTAssertEqual(readings.map(\.pid), [10])
        XCTAssertNil(readings[0].percent)
        XCTAssertEqual(readings[0].text, "—")
    }

    func testUnreadableGPUTimeIsMissingNotZero() {
        var properties = client(pid: 3, name: "Mail", times: [1_000_000_000])
        properties["AppUsage"] = [["accumulatedGPUTime": "nope"]]
        let readings = GPUShareDecoder.shares(
            previous: [GPUShareDecoder.parse(id: 7, properties: client(pid: 3, name: "Mail", times: [1_000_000_000]))],
            current: [GPUShareDecoder.parse(id: 7, properties: properties)],
            elapsedNanoseconds: 1_000_000_000
        )

        XCTAssertEqual(readings.map(\.pid), [3])
        XCTAssertNil(readings[0].percent)
        XCTAssertEqual(readings[0].text, "—")
    }

    func testZeroDeltaIsARealZero() {
        let readings = GPUShareDecoder.shares(
            previous: [GPUShareDecoder.parse(id: 1, properties: client(pid: 6, name: "Notes", times: [4_000_000_000]))],
            current: [GPUShareDecoder.parse(id: 1, properties: client(pid: 6, name: "Notes", times: [4_000_000_000]))],
            elapsedNanoseconds: 1_000_000_000
        )

        XCTAssertEqual(readings.map(\.pid), [6])
        XCTAssertEqual(readings[0].percent, 0)
        XCTAssertEqual(readings[0].text, "0.0%")
    }

    private func client(pid: Int32, name: String, times: [UInt64]) -> [String: Any] {
        [
            "IOUserClientCreator": "pid \(pid), \(name)",
            "AppUsage": times.map { ["accumulatedGPUTime": $0] },
        ]
    }
}
