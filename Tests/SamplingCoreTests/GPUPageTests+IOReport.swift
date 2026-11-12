import XCTest
@testable import SamplingCore

extension GPUPageTests {
    func testMissingDeviceKeyUsesTheSameNodeIOReportPercent() {
        let page = succeed([
            node([
                "In use system memory": .bytes(80),
                "Renderer Utilization %": .number(70),
                "Tiler Utilization %": .number(30),
            ], ioReportDevicePercent: 12.5),
            node([
                "In use system memory": .bytes(10),
                "Device Utilization %": .number(44),
            ], ioReportDevicePercent: 90),
        ], at: 1)

        XCTAssertEqual(page.utilizationPercent, 12.5)
        XCTAssertEqual(page.inUseMemoryBytes, 80)
        XCTAssertEqual(page.utilizationText, "12.5%")
        XCTAssertEqual(page.memoryText, "80 字节")
        XCTAssertEqual(page.history.samples.map(\.value), [12.5])
        XCTAssertEqual(page.chrome, .readings)
    }

    func testPresentDeviceKeyIgnoresTheSameNodeIOReportPercent() {
        let inRange = succeed([
            node([
                "In use system memory": .bytes(4),
                "Device Utilization %": .number(20),
            ], ioReportDevicePercent: 80),
        ], at: 1)
        XCTAssertEqual(inRange.utilizationPercent, 20)
        XCTAssertEqual(inRange.inUseMemoryBytes, 4)
        XCTAssertEqual(inRange.history.samples.map(\.value), [20])

        for value in [150.0, -1.0, Double.nan, Double.infinity] {
            let page = succeed([
                node([
                    "In use system memory": .bytes(80),
                    "Device Utilization %": .number(value),
                ], ioReportDevicePercent: 12.5),
            ], at: 2)
            XCTAssertNil(page.utilizationPercent, "\(value)")
            XCTAssertEqual(page.inUseMemoryBytes, 80, "\(value)")
            XCTAssertEqual(page.utilizationText, "—", "\(value)")
            XCTAssertTrue(page.history.samples.isEmpty, "\(value)")
        }

        let unreadable = succeed([
            node([
                "In use system memory": .bytes(4),
                "Device Utilization %": .unreadable,
            ], ioReportDevicePercent: 12.5),
        ], at: 3)
        XCTAssertNil(unreadable.utilizationPercent)
        XCTAssertEqual(unreadable.inUseMemoryBytes, 4)
        XCTAssertTrue(unreadable.history.samples.isEmpty)
    }

    func testOutOfRangeDeviceKeyLosesToALaterIOReportNode() {
        let page = succeed([
            node([
                "Device Utilization %": .number(200),
            ], ioReportDevicePercent: 10),
            node([:], ioReportDevicePercent: 40),
        ], at: 1)

        XCTAssertEqual(page.utilizationPercent, 40)
        XCTAssertNil(page.inUseMemoryBytes)
        XCTAssertEqual(page.memoryText, "—")
        XCTAssertEqual(page.history.samples.map(\.value), [40])
    }

    func testFirstIOReportNodeWinsOverALaterDeviceKey() {
        let page = succeed([
            node([:], ioReportDevicePercent: 40),
            node(["Device Utilization %": .number(8)]),
        ], at: 1)

        XCTAssertEqual(page.utilizationPercent, 40)
        XCTAssertNil(page.inUseMemoryBytes)
        XCTAssertEqual(page.history.samples.map(\.value), [40])
    }

    func testIOReportOutsideRangeIsMissingAndDoesNotMakeTheNodeEligible() {
        let outside: [Double?] = [nil, 101, -0.1, Double.nan, Double.infinity, -Double.infinity]
        for value in outside {
            let only = succeed([
                node([:], ioReportDevicePercent: value),
            ], at: 1)
            XCTAssertNil(only.utilizationPercent, "\(String(describing: value))")
            XCTAssertNil(only.inUseMemoryBytes, "\(String(describing: value))")
            XCTAssertEqual(only.utilizationText, "—", "\(String(describing: value))")
            XCTAssertTrue(only.history.samples.isEmpty, "\(String(describing: value))")

            let skipped = succeed([
                node([:], ioReportDevicePercent: value),
                node(["Device Utilization %": .number(15)]),
            ], at: 2)
            XCTAssertEqual(skipped.utilizationPercent, 15, "\(String(describing: value))")
            XCTAssertEqual(skipped.history.samples.map(\.value), [15], "\(String(describing: value))")
        }
    }

    func testMemoryWinnerDoesNotBorrowAnotherNodesIOReport() {
        let page = succeed([
            node(["In use system memory": .bytes(80)]),
            node([:], ioReportDevicePercent: 55),
        ], at: 1)

        XCTAssertNil(page.utilizationPercent)
        XCTAssertEqual(page.inUseMemoryBytes, 80)
        XCTAssertEqual(page.memoryText, "80 字节")
        XCTAssertTrue(page.history.samples.isEmpty)

        let unreadableMemory = succeed([
            node([
                "In use system memory": .unreadable,
            ], ioReportDevicePercent: 12.5),
            node(["Device Utilization %": .number(30)]),
        ], at: 2)
        XCTAssertEqual(unreadableMemory.utilizationPercent, 12.5)
        XCTAssertNil(unreadableMemory.inUseMemoryBytes)
        XCTAssertEqual(unreadableMemory.history.samples.map(\.value), [12.5])
    }

    func testIOReportZeroAndOneHundredRecordOnTheCurve() {
        let idle = succeed([
            node([
                "In use system memory": .bytes(0),
            ], ioReportDevicePercent: 0),
        ], at: 1)
        XCTAssertEqual(idle.utilizationPercent, 0)
        XCTAssertEqual(idle.utilizationText, "0.0%")
        XCTAssertEqual(idle.memoryText, "0 字节")
        XCTAssertEqual(idle.history.samples.map(\.value), [0])

        let full = succeed([
            node([:], ioReportDevicePercent: 100),
        ], at: 2)
        XCTAssertEqual(full.utilizationPercent, 100)
        XCTAssertEqual(full.utilizationText, "100.0%")
        XCTAssertNil(full.inUseMemoryBytes)
        XCTAssertEqual(full.history.samples.map(\.value), [100])
    }
}
