import XCTest
@testable import SamplingCore

/// Process memory is footprint when that read succeeded, including a real zero.
/// Nil is the only resident fallback. Not a Darwin call.
final class ProcessMemoryChoiceTests: XCTestCase {
    func testFootprintWinsWhenPresentWhetherLargerOrSmallerThanResident() {
        let larger = ProcessMemoryChoice.project(footprint: 1_600, resident: 100)
        XCTAssertEqual(larger.bytes, 1_600)
        XCTAssertEqual(larger.source, .footprint)

        let smaller = ProcessMemoryChoice.project(footprint: 50, resident: 800)
        XCTAssertEqual(smaller.bytes, 50)
        XCTAssertEqual(smaller.source, .footprint)
    }

    func testNilFootprintFallsBackToResident() {
        let choice = ProcessMemoryChoice.project(footprint: nil, resident: 800)
        XCTAssertEqual(choice.bytes, 800)
        XCTAssertEqual(choice.source, .resident)
    }

    func testRealZeroFootprintStaysZero() {
        let choice = ProcessMemoryChoice.project(footprint: 0, resident: 800)
        XCTAssertEqual(choice.bytes, 0)
        XCTAssertEqual(choice.source, .footprint)
    }

    func testProcessRowDefaultsMemorySourceToFootprint() {
        let row = ProcessRow(
            pid: 1,
            name: "Notes",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 10,
            threadCount: 1
        )
        XCTAssertEqual(row.memoryBytes, 10)
        XCTAssertEqual(row.memorySource, .footprint)

        let fallback = ProcessRow(
            pid: 2,
            name: "kernel",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 40,
            memorySource: .resident,
            threadCount: 1
        )
        XCTAssertEqual(fallback.memoryBytes, 40)
        XCTAssertEqual(fallback.memorySource, .resident)
    }
}
