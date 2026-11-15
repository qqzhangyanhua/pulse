import XCTest
@testable import SamplingCore

/// `voltage-states9` is little-endian Hz, mV uint32 pairs. Index 0 is OFF.
final class VoltageStates9Tests: XCTestCase {
    func testMeasuredM1ProTableParsesSevenEntries() {
        // Hertz column is the measured M1 Pro table. Millivolts only lock pair order.
        let bytes = Data([
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x40, 0xAB, 0x2F, 0x17, 0x58, 0x02, 0x00, 0x00,
            0x80, 0xC5, 0xF7, 0x1C, 0x8A, 0x02, 0x00, 0x00,
            0x00, 0xB2, 0x9F, 0x26, 0xBC, 0x02, 0x00, 0x00,
            0x80, 0x56, 0x5F, 0x2E, 0xEE, 0x02, 0x00, 0x00,
            0x00, 0x8B, 0xEF, 0x39, 0x20, 0x03, 0x00, 0x00,
            0x00, 0x64, 0x3F, 0x4D, 0x84, 0x03, 0x00, 0x00,
        ])
        let table = VoltageStates9.parse(bytes)
        XCTAssertEqual(table?.count, 7)
        XCTAssertEqual(table?.map(\.hertz), [
            0,
            389_000_000,
            486_000_000,
            648_000_000,
            778_000_000,
            972_000_000,
            1_296_000_000,
        ])
        XCTAssertEqual(table?.map(\.millivolts), [0, 600, 650, 700, 750, 800, 900])
    }

    func testEmptyOrTruncatedBytesStayNil() {
        XCTAssertNil(VoltageStates9.parse(Data()))
        XCTAssertNil(VoltageStates9.parse(Data([0x40, 0xAB, 0x2F, 0x17])))
        XCTAssertNil(VoltageStates9.parse(Data(count: 12)))
    }
}
