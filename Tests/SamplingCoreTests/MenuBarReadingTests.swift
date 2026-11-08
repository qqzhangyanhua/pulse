import XCTest
@testable import SamplingCore

final class MenuBarReadingTests: XCTestCase {
    func testDotModeTitleStaysEmptyEvenWhenReadingsExist() {
        XCTAssertEqual(
            MenuBarReadingTitle.string(mode: .dot, usedBytes: 13_261_991_936, cpuPercent: 12.5),
            ""
        )
        XCTAssertEqual(
            MenuBarReadingTitle.string(mode: .dot, usedBytes: nil, cpuPercent: nil),
            ""
        )
        XCTAssertNotEqual(
            MenuBarReadingTitle.string(mode: .dot, usedBytes: nil, cpuPercent: nil),
            "—"
        )
    }

    func testUsedMemoryTitleUsesByteFormatAndDashWhenMissing() {
        XCTAssertEqual(
            MenuBarReadingTitle.string(mode: .usedMemory, usedBytes: 13_261_991_936, cpuPercent: 12.5),
            "12.35 GB"
        )
        XCTAssertEqual(
            MenuBarReadingTitle.string(mode: .usedMemory, usedBytes: 524_288_000, cpuPercent: nil),
            "500 MB"
        )
        XCTAssertEqual(
            MenuBarReadingTitle.string(mode: .usedMemory, usedBytes: 0, cpuPercent: 4),
            "0 字节"
        )
        XCTAssertEqual(
            MenuBarReadingTitle.string(mode: .usedMemory, usedBytes: nil, cpuPercent: 12.5),
            "—"
        )
        XCTAssertFalse(
            MenuBarReadingTitle.string(mode: .usedMemory, usedBytes: 13_261_991_936, cpuPercent: 99).contains("99")
        )
        XCTAssertFalse(
            MenuBarReadingTitle.string(mode: .usedMemory, usedBytes: nil, cpuPercent: nil).contains("0")
        )
    }

    func testCPUTitleUsesPercentTextAndDashWhenMissing() {
        XCTAssertEqual(
            MenuBarReadingTitle.string(mode: .cpu, usedBytes: 13_261_991_936, cpuPercent: 12.5),
            "12.5%"
        )
        XCTAssertEqual(
            MenuBarReadingTitle.string(mode: .cpu, usedBytes: 0, cpuPercent: 0),
            "0.0%"
        )
        XCTAssertEqual(
            MenuBarReadingTitle.string(mode: .cpu, usedBytes: 13_261_991_936, cpuPercent: nil),
            "—"
        )
        XCTAssertFalse(
            MenuBarReadingTitle.string(mode: .cpu, usedBytes: 13_261_991_936, cpuPercent: 12.5).contains("GB")
        )
        XCTAssertFalse(
            MenuBarReadingTitle.string(mode: .cpu, usedBytes: nil, cpuPercent: nil).contains("0")
        )
    }

    func testAbsentOrUnknownStoredModeStaysDotOnly() {
        XCTAssertEqual(MenuBarReadingMode.resolved(stored: nil), .dot)
        XCTAssertEqual(MenuBarReadingMode.resolved(stored: ""), .dot)
        XCTAssertEqual(MenuBarReadingMode.resolved(stored: "used-memory"), .dot)
        XCTAssertEqual(MenuBarReadingMode.resolved(stored: "dot"), .dot)
        XCTAssertEqual(MenuBarReadingMode.resolved(stored: "usedMemory"), .usedMemory)
        XCTAssertEqual(MenuBarReadingMode.resolved(stored: "cpu"), .cpu)
        XCTAssertEqual(
            MenuBarReadingMode.allCases.map(\.settingsLabel),
            ["仅色点", "色点 + 已用内存", "色点 + CPU"]
        )
    }

    func testPreferenceRoundTripKeepsTheStoredModeAndDefaultsToDot() {
        let suite = "pulse.menuBarReading.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertEqual(MenuBarReadingPreference.mode(in: defaults), .dot)
        MenuBarReadingPreference.store(.cpu, in: defaults)
        XCTAssertEqual(MenuBarReadingPreference.mode(in: defaults), .cpu)
        MenuBarReadingPreference.store(.usedMemory, in: defaults)
        XCTAssertEqual(MenuBarReadingPreference.mode(in: defaults), .usedMemory)
        defaults.removePersistentDomain(forName: suite)
        XCTAssertEqual(MenuBarReadingPreference.mode(in: defaults), .dot)
    }

    func testReadingLayoutIsSquareOnlyForTheDot() {
        XCTAssertEqual(MenuBarStatusItemLayout.resolve(mode: .dot), .dot)
        XCTAssertEqual(MenuBarStatusItemLayout.resolve(mode: .usedMemory), .reading)
        XCTAssertEqual(MenuBarStatusItemLayout.resolve(mode: .cpu), .reading)
    }
}
