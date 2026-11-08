import XCTest
@testable import SamplingCore

final class KernelPressureTests: XCTestCase {
    func testKernelValueOneMapsToNormal() {
        XCTAssertEqual(KernelPressure.level(from: 1), .normal)
    }

    func testKernelValueTwoMapsToElevated() {
        XCTAssertEqual(KernelPressure.level(from: 2), .elevated)
    }

    func testKernelValueFourMapsToElevated() {
        XCTAssertEqual(KernelPressure.level(from: 4), .elevated)
    }

    func testUnknownKernelValuesStayUnmapped() {
        XCTAssertNil(KernelPressure.level(from: 0))
        XCTAssertNil(KernelPressure.level(from: 3))
        XCTAssertNil(KernelPressure.level(from: -1))
        XCTAssertNil(KernelPressure.level(from: 99))
    }

    func testNilKernelReadUsesTheRatioFallback() {
        assertRatioFallback(reading: nil)
        let failed = KernelPressureSample(status: 1, value: 1)
        XCTAssertEqual(
            KernelPressure.resolve(reading: failed, usedRatio: 0.88, compressedRatio: 0),
            .elevated
        )
    }

    func testUnknownKernelValueUsesTheRatioFallback() {
        let unknown = KernelPressureSample(status: 0, value: 3)
        assertRatioFallback(reading: unknown)
        let zero = KernelPressureSample(status: 0, value: 0)
        XCTAssertEqual(
            KernelPressure.resolve(reading: zero, usedRatio: 0.88, compressedRatio: 0),
            .elevated
        )
        let negative = KernelPressureSample(status: 0, value: -1)
        XCTAssertEqual(
            KernelPressure.resolve(reading: negative, usedRatio: 0.5, compressedRatio: 0),
            .normal
        )
        let larger = KernelPressureSample(status: 0, value: 99)
        XCTAssertEqual(
            KernelPressure.resolve(reading: larger, usedRatio: 0.99, compressedRatio: 0),
            .elevated
        )
    }

    func testMappedKernelLevelSkipsTheRatioFallback() {
        let normal = KernelPressureSample(status: 0, value: 1)
        XCTAssertEqual(
            KernelPressure.resolve(reading: normal, usedRatio: 0.99, compressedRatio: 0.5),
            .normal
        )
        let warning = KernelPressureSample(status: 0, value: 2)
        XCTAssertEqual(
            KernelPressure.resolve(reading: warning, usedRatio: 0, compressedRatio: 0),
            .elevated
        )
        let critical = KernelPressureSample(status: 0, value: 4)
        XCTAssertEqual(
            KernelPressure.resolve(reading: critical, usedRatio: 0, compressedRatio: 0),
            .elevated
        )
    }

    private func assertRatioFallback(reading: KernelPressureSample?) {
        XCTAssertEqual(
            KernelPressure.resolve(reading: reading, usedRatio: 0.88, compressedRatio: 0),
            .elevated
        )
        XCTAssertEqual(
            KernelPressure.resolve(reading: reading, usedRatio: 0, compressedRatio: 0.18),
            .elevated
        )
        XCTAssertEqual(
            KernelPressure.resolve(reading: reading, usedRatio: 0.87, compressedRatio: 0.17),
            .normal
        )
    }
}
