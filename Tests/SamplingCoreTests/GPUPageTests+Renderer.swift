import XCTest
@testable import SamplingCore

/// Renderer, tiler, and recovery stay on the accelerator already chosen for utilization.
extension GPUPageTests {
    func testRendererAndTilerComeFromTheSelectedNodeAndDoNotChangeUtilization() {
        let page = succeed([
            node([
                "In use system memory": .bytes(100),
                "Device Utilization %": .number(11),
                "Renderer Utilization %": .number(80),
                "Tiler Utilization %": .number(70),
                "recoveryCount": .number(9),
            ]),
            node([
                "In use system memory": .bytes(250),
                "Device Utilization %": .number(10),
                "Renderer Utilization %": .number(12.34),
                "Tiler Utilization %": .number(0),
                "recoveryCount": .number(2),
            ]),
        ], at: 10)

        XCTAssertEqual(page.utilizationPercent, 10)
        XCTAssertEqual(page.utilizationText, "10.0%")
        XCTAssertNotEqual(page.utilizationPercent, 12.34)
        XCTAssertNotEqual(page.utilizationPercent, 6.17)
        XCTAssertEqual(page.rendererPercent, 12.34)
        XCTAssertEqual(page.tilerPercent, 0)
        XCTAssertEqual(page.rendererText, "12.3%")
        XCTAssertEqual(page.tilerText, "0.0%")
        XCTAssertEqual(page.history.samples.map(\.value), [10])
        XCTAssertFalse(page.history.samples.map(\.value).contains(12.34))
        XCTAssertFalse(page.history.samples.map(\.value).contains(0))
    }

    func testRendererAndTilerOutsideZeroToOneHundredStayMissing() {
        for value in [-0.1, 100.1, Double.infinity, -Double.infinity, Double.nan] {
            let page = succeed([
                node([
                    "In use system memory": .bytes(8),
                    "Device Utilization %": .number(10),
                    "Renderer Utilization %": .number(value),
                    "Tiler Utilization %": .unreadable,
                ]),
                node([
                    "Renderer Utilization %": .number(40),
                    "Tiler Utilization %": .number(40),
                ]),
            ], at: 1)
            XCTAssertNil(page.rendererPercent, "\(value)")
            XCTAssertNil(page.tilerPercent, "\(value)")
            XCTAssertEqual(page.rendererText, "—", "\(value)")
            XCTAssertEqual(page.tilerText, "—", "\(value)")
            XCTAssertEqual(page.utilizationPercent, 10, "\(value)")
            XCTAssertEqual(page.history.samples.map(\.value), [10], "\(value)")
        }

        let ends = succeed([
            node([
                "Device Utilization %": .number(100),
                "Renderer Utilization %": .number(0),
                "Tiler Utilization %": .number(100),
            ]),
        ], at: 2)
        XCTAssertEqual(ends.rendererText, "0.0%")
        XCTAssertEqual(ends.tilerText, "100.0%")
        XCTAssertEqual(ends.utilizationText, "100.0%")
    }

    func testSelectedMemoryNodeKeepsItsEnginesWhenUtilizationIsMissing() {
        let page = succeed([
            node([
                "In use system memory": .bytes(80),
                "Device Utilization %": .number(200),
                "Renderer Utilization %": .number(33),
                "Tiler Utilization %": .number(4),
                "recoveryCount": .number(1),
            ]),
            node([
                "Device Utilization %": .number(44),
                "Renderer Utilization %": .number(9),
                "Tiler Utilization %": .number(8),
                "recoveryCount": .number(6),
            ]),
        ], at: 1)

        XCTAssertNil(page.utilizationPercent)
        XCTAssertEqual(page.rendererPercent, 33)
        XCTAssertEqual(page.tilerPercent, 4)
        XCTAssertEqual(page.recoveryCount, 1)
        XCTAssertTrue(page.history.samples.isEmpty)
    }

    func testUnselectedNodeDoesNotSupplyRendererTilerOrRecovery() {
        let page = succeed([
            node(["Device Utilization %": .number(101)]),
            node([
                "Renderer Utilization %": .number(40),
                "Tiler Utilization %": .number(20),
                "recoveryCount": .number(5),
            ]),
        ], at: 1)

        XCTAssertNil(page.utilizationPercent)
        XCTAssertNil(page.rendererPercent)
        XCTAssertNil(page.tilerPercent)
        XCTAssertNil(page.recoveryCount)
        XCTAssertEqual(page.rendererText, "—")
        XCTAssertEqual(page.tilerText, "—")
        XCTAssertEqual(page.recoveryText, "—")
        XCTAssertTrue(page.history.samples.isEmpty)
    }

    func testRecoveryCountMustBeANonNegativeInteger() {
        let zero = succeed([
            node([
                "Device Utilization %": .number(1),
                "recoveryCount": .number(0),
            ]),
        ], at: 1)
        XCTAssertEqual(zero.recoveryCount, 0)
        XCTAssertEqual(zero.recoveryText, "0 次")

        let whole = succeed([
            node([
                "Device Utilization %": .number(1),
                "recoveryCount": .number(7),
            ]),
        ], at: 2)
        XCTAssertEqual(whole.recoveryCount, 7)
        XCTAssertEqual(whole.recoveryText, "7 次")

        for value in [-1.0, 1.5, Double.nan, Double.infinity, -Double.infinity, 1e20] {
            let page = succeed([
                node([
                    "In use system memory": .bytes(16),
                    "Device Utilization %": .number(3),
                    "recoveryCount": .number(value),
                ]),
                node(["recoveryCount": .number(4)]),
            ], at: 3)
            XCTAssertNil(page.recoveryCount, "\(value)")
            XCTAssertEqual(page.recoveryText, "—", "\(value)")
            XCTAssertEqual(page.utilizationPercent, 3, "\(value)")
        }

        let unreadable = succeed([
            node([
                "Device Utilization %": .number(3),
                "recoveryCount": .unreadable,
            ]),
        ], at: 4)
        XCTAssertNil(unreadable.recoveryCount)
        XCTAssertEqual(unreadable.recoveryText, "—")

        let bytes = succeed([
            node([
                "Device Utilization %": .number(3),
                "recoveryCount": .bytes(2),
            ]),
        ], at: 5)
        XCTAssertNil(bytes.recoveryCount)
        XCTAssertEqual(bytes.recoveryText, "—")
    }

    func testFailedFrameKeepsRendererTilerAndRecovery() {
        let current = succeed([
            node([
                "In use system memory": .bytes(250),
                "Device Utilization %": .number(64),
                "Renderer Utilization %": .number(12.5),
                "Tiler Utilization %": .number(0),
                "recoveryCount": .number(3),
            ]),
        ], at: 1)
        XCTAssertEqual(current.rendererText, "12.5%")
        XCTAssertEqual(current.tilerText, "0.0%")
        XCTAssertEqual(current.recoveryText, "3 次")
        XCTAssertEqual(current.history.samples.map(\.value), [64])

        let failed = GPUPageProjection.apply(
            nodes: [node([
                "In use system memory": .bytes(1),
                "Device Utilization %": .number(1),
                "Renderer Utilization %": .number(99),
                "Tiler Utilization %": .number(88),
                "recoveryCount": .number(9),
            ])],
            frame: .failed,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: current,
            transition: .stayed
        )
        XCTAssertEqual(failed.chrome, .readings)
        XCTAssertEqual(failed.rendererPercent, 12.5)
        XCTAssertEqual(failed.tilerPercent, 0)
        XCTAssertEqual(failed.recoveryCount, 3)
        XCTAssertEqual(failed.utilizationPercent, 64)
        XCTAssertEqual(failed.history.samples.map(\.value), [64])

        let left = GPUPageProjection.apply(
            nodes: [node([
                "Device Utilization %": .number(2),
                "Renderer Utilization %": .number(1),
                "recoveryCount": .number(8),
            ])],
            frame: .succeeded,
            sampledAt: Date(timeIntervalSince1970: 3),
            current: current,
            transition: .justLeft
        )
        XCTAssertEqual(left.rendererPercent, 12.5)
        XCTAssertEqual(left.tilerPercent, 0)
        XCTAssertEqual(left.recoveryCount, 3)
        XCTAssertEqual(left.history.samples.map(\.value), [64])

        let replaced = succeed([
            node([
                "Device Utilization %": .number(4),
                "recoveryCount": .number(0),
            ]),
        ], at: 4, current: current)
        XCTAssertNil(replaced.rendererPercent)
        XCTAssertNil(replaced.tilerPercent)
        XCTAssertEqual(replaced.rendererText, "—")
        XCTAssertEqual(replaced.tilerText, "—")
        XCTAssertEqual(replaced.recoveryCount, 0)
        XCTAssertEqual(replaced.recoveryText, "0 次")
        XCTAssertEqual(replaced.utilizationPercent, 4)
        XCTAssertEqual(replaced.history.samples.map(\.value), [64, 4])
    }

    func testEngineCopyNamesTheLabelsAndNotARecoveryTime() {
        XCTAssertEqual(GPUPageCopy.renderer, "渲染器")
        XCTAssertEqual(GPUPageCopy.tiler, "分块器")
        XCTAssertEqual(GPUPageCopy.recovery, "GPU 恢复次数")
        XCTAssertEqual(GPUPageCopy.recoveryCaption, "GPU 卡住后，驱动重置它的次数")
        XCTAssertEqual(GPUPageProjection.rendererUtilizationKey, "Renderer Utilization %")
        XCTAssertEqual(GPUPageProjection.tilerUtilizationKey, "Tiler Utilization %")
        XCTAssertEqual(GPUPageProjection.recoveryCountKey, "recoveryCount")
        let blob = [
            GPUPageCopy.renderer,
            GPUPageCopy.tiler,
            GPUPageCopy.recovery,
            GPUPageCopy.recoveryCaption,
        ].joined(separator: "\n")
        XCTAssertFalse(blob.contains("最近一次"))
        XCTAssertFalse(blob.contains("自开机以来"))
        XCTAssertFalse(blob.contains("平均"))
    }
}
