import XCTest
@testable import SamplingCore

/// GPU page projection. Nodes, frame outcome, and page transition in;
/// the two readings, the curve, and the empty state out. No IOKit.
final class GPUPageTests: XCTestCase {
    func testMaxInUseMemoryWinsAndBothNumbersComeFromThatNode() {
        let page = succeed([
            node([
                "In use system memory": .bytes(100),
                "Device Utilization %": .number(11),
            ]),
            node([
                "In use system memory": .bytes(250),
                "Device Utilization %": .number(64),
                "Renderer Utilization %": .number(99),
                "Alloc system memory": .bytes(9_000),
            ]),
            node([
                "In use system memory": .bytes(40),
                "Device Utilization %": .number(3),
            ]),
        ], at: 10)

        XCTAssertEqual(page.utilizationPercent, 64)
        XCTAssertEqual(page.inUseMemoryBytes, 250)
        XCTAssertEqual(page.utilizationText, "64.0%")
        XCTAssertEqual(page.memoryText, "250 字节")
        XCTAssertNotEqual(page.inUseMemoryBytes, 390)
        XCTAssertEqual(page.history.samples.map(\.value), [64])
        XCTAssertFalse(page.showsCurve)
        XCTAssertEqual(page.chrome, .readings)
        XCTAssertTrue(page.visitSucceeded)
    }

    func testTiedInUseMemoryKeepsTheFirstNodeAndDoesNotBorrow() {
        let page = succeed([
            node([
                "In use system memory": .bytes(500),
                "Device Utilization %": .number(1),
            ]),
            node([
                "In use system memory": .bytes(500),
                "Device Utilization %": .number(90),
            ]),
        ], at: 1)

        XCTAssertEqual(page.utilizationPercent, 1)
        XCTAssertEqual(page.inUseMemoryBytes, 500)
        XCTAssertEqual(page.utilizationText, "1.0%")
    }

    func testMissingDeviceKeyOnTheMemoryNodeStaysMissing() {
        let page = succeed([
            node([
                "In use system memory": .bytes(80),
                "Renderer Utilization %": .number(70),
                "Tiler Utilization %": .number(30),
            ]),
            node([
                "Device Utilization %": .number(44),
            ]),
        ], at: 1)

        XCTAssertNil(page.utilizationPercent)
        XCTAssertEqual(page.inUseMemoryBytes, 80)
        XCTAssertEqual(page.utilizationText, "—")
        XCTAssertEqual(page.memoryText, "80 字节")
        XCTAssertTrue(page.history.samples.isEmpty)
        XCTAssertTrue(page.visitSucceeded)
        XCTAssertEqual(page.chrome, .readings)
    }

    func testNoInUseMemoryTakesTheFirstDevicePercentInRange() {
        let page = succeed([
            node([
                "Device Utilization %": .number(150),
                "Renderer Utilization %": .number(12),
            ]),
            node([
                "Device Utilization %": .number(10),
                "Tiler Utilization %": .number(99),
            ]),
            node([
                "Device Utilization %": .number(90),
            ]),
        ], at: 2)

        XCTAssertEqual(page.utilizationPercent, 10)
        XCTAssertNil(page.inUseMemoryBytes)
        XCTAssertEqual(page.utilizationText, "10.0%")
        XCTAssertEqual(page.memoryText, "—")
        XCTAssertEqual(page.history.samples.map(\.value), [10])
    }

    func testNoEligibleNodeLeavesBothNumbersMissing() {
        let page = succeed([
            node(["Device Utilization %": .number(101)]),
            node(["Device Utilization %": .number(.nan)]),
            node(["Renderer Utilization %": .number(40), "Alloc system memory": .bytes(4_096)]),
            node([:]),
        ], at: 3)

        XCTAssertNil(page.utilizationPercent)
        XCTAssertNil(page.inUseMemoryBytes)
        XCTAssertEqual(page.utilizationText, "—")
        XCTAssertEqual(page.memoryText, "—")
        XCTAssertTrue(page.history.samples.isEmpty)
        XCTAssertEqual(page.chrome, .readings)
        XCTAssertTrue(page.visitSucceeded)
    }

    func testZeroAndOneHundredAreRealReadings() {
        let idle = succeed([
            node([
                "In use system memory": .bytes(0),
                "Device Utilization %": .number(0),
            ]),
        ], at: 1)
        XCTAssertEqual(idle.utilizationText, "0.0%")
        XCTAssertEqual(idle.memoryText, "0 字节")
        XCTAssertEqual(idle.history.samples.map(\.value), [0])

        let full = succeed([
            node(["Device Utilization %": .number(100)]),
        ], at: 2)
        XCTAssertEqual(full.utilizationPercent, 100)
        XCTAssertEqual(full.utilizationText, "100.0%")
        XCTAssertNil(full.inUseMemoryBytes)
    }

    func testOutOfRangeAndNonFiniteUtilizationStayMissing() {
        for value in [-0.1, 100.1, Double.infinity, -Double.infinity, Double.nan] {
            let page = succeed([
                node([
                    "In use system memory": .bytes(1_048_576),
                    "Device Utilization %": .number(value),
                    "Renderer Utilization %": .number(8),
                ]),
            ], at: 1)
            XCTAssertNil(page.utilizationPercent, "\(value)")
            XCTAssertEqual(page.utilizationText, "—", "\(value)")
            XCTAssertEqual(page.inUseMemoryBytes, 1_048_576, "\(value)")
            XCTAssertEqual(page.memoryText, "1 MB", "\(value)")
            XCTAssertTrue(page.history.samples.isEmpty, "\(value)")
        }
    }

    func testRendererTilerAndAllocDoNotBecomeTheReadings() {
        let onlyEngines = succeed([
            node([
                "Renderer Utilization %": .number(40),
                "Tiler Utilization %": .number(60),
                "Alloc system memory": .bytes(8_192),
            ]),
        ], at: 1)
        XCTAssertNil(onlyEngines.utilizationPercent)
        XCTAssertNil(onlyEngines.inUseMemoryBytes)
        XCTAssertTrue(onlyEngines.history.samples.isEmpty)

        let mixed = succeed([
            node([
                "Device Utilization %": .number(10),
                "Renderer Utilization %": .number(50),
                "Tiler Utilization %": .number(90),
                "In use system memory": .bytes(2_048),
                "Alloc system memory": .bytes(99_999),
            ]),
        ], at: 2)
        XCTAssertEqual(mixed.utilizationPercent, 10)
        XCTAssertEqual(mixed.inUseMemoryBytes, 2_048)
        XCTAssertEqual(mixed.memoryText, "2 KB")
    }

    func testInUseValueThatIsNotAByteCountStaysMissingAndStillOwnsTheNode() {
        let page = succeed([
            node([
                "In use system memory": .unreadable,
                "Device Utilization %": .number(200),
            ]),
            node([
                "Device Utilization %": .number(30),
            ]),
        ], at: 1)

        XCTAssertNil(page.utilizationPercent)
        XCTAssertNil(page.inUseMemoryBytes)
        XCTAssertEqual(page.utilizationText, "—")
        XCTAssertEqual(page.memoryText, "—")
        XCTAssertTrue(page.history.samples.isEmpty)
    }

    func testANumberInTheMemoryKeyIsNotBytesAndLosesToARealByteCount() {
        let page = succeed([
            node([
                "In use system memory": .number(9_999),
                "Device Utilization %": .number(4),
            ]),
            node([
                "In use system memory": .bytes(32),
                "Device Utilization %": .number(7),
            ]),
        ], at: 1)

        XCTAssertEqual(page.utilizationPercent, 7)
        XCTAssertEqual(page.inUseMemoryBytes, 32)
        XCTAssertEqual(page.memoryText, "32 字节")
    }

    func testJustEnteredDropsThePreviousVisitBeforeThisFrame() {
        let previous = succeed([
            node([
                "In use system memory": .bytes(400),
                "Device Utilization %": .number(15),
            ]),
        ], at: 1)
        let held = succeed([
            node([
                "In use system memory": .bytes(400),
                "Device Utilization %": .number(16),
            ]),
        ], at: 2, current: previous)
        XCTAssertEqual(held.history.samples.count, 2)

        let waiting = GPUPageProjection.apply(
            nodes: [node(["Device Utilization %": .number(70)])],
            frame: .pending,
            sampledAt: Date(timeIntervalSince1970: 3),
            current: held,
            transition: .justEntered
        )
        XCTAssertEqual(waiting.chrome, .skeleton)
        XCTAssertNil(waiting.utilizationPercent)
        XCTAssertNil(waiting.inUseMemoryBytes)
        XCTAssertFalse(waiting.visitSucceeded)
        XCTAssertTrue(waiting.history.samples.isEmpty)
        XCTAssertFalse(waiting.showsCurve)

        let failed = GPUPageProjection.apply(
            frame: .failed,
            sampledAt: Date(timeIntervalSince1970: 3),
            current: held,
            transition: .justEntered
        )
        XCTAssertEqual(failed.chrome, .samplingFailure)
        XCTAssertNil(failed.utilizationPercent)
        XCTAssertNil(failed.inUseMemoryBytes)
        XCTAssertFalse(failed.visitSucceeded)
        XCTAssertTrue(failed.history.samples.isEmpty)

        let entered = succeed([
            node([
                "In use system memory": .bytes(8),
                "Device Utilization %": .number(2),
            ]),
        ], at: 4, current: held, transition: .justEntered)
        XCTAssertEqual(entered.utilizationPercent, 2)
        XCTAssertEqual(entered.inUseMemoryBytes, 8)
        XCTAssertEqual(entered.history.samples.map(\.value), [2])
        XCTAssertEqual(entered.chrome, .readings)
        XCTAssertTrue(entered.visitSucceeded)
    }

    func testJustLeftClearsTheCurveAndDoesNotPublishThisFrame() {
        let current = succeed([
            node([
                "In use system memory": .bytes(100),
                "Device Utilization %": .number(10),
            ]),
        ], at: 1)
        let left = GPUPageProjection.apply(
            nodes: [node([
                "In use system memory": .bytes(900),
                "Device Utilization %": .number(80),
            ])],
            frame: .succeeded,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: current,
            transition: .justLeft
        )

        XCTAssertEqual(left.utilizationPercent, 10)
        XCTAssertEqual(left.inUseMemoryBytes, 100)
        XCTAssertTrue(left.history.samples.isEmpty)
        XCTAssertNotEqual(left.utilizationPercent, 80)
    }

    func testStayedFailureKeepsASuccessfulVisitAndDoesNotAppend() {
        let current = succeed([
            node([
                "In use system memory": .bytes(512),
                "Device Utilization %": .number(12.5),
            ]),
        ], at: 1)
        XCTAssertEqual(current.utilizationText, "12.5%")
        XCTAssertEqual(current.memoryText, "512 字节")

        let failed = GPUPageProjection.apply(
            nodes: [node(["Device Utilization %": .number(99)])],
            frame: .failed,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: current,
            transition: .stayed
        )
        XCTAssertEqual(failed.chrome, .readings)
        XCTAssertEqual(failed.utilizationPercent, 12.5)
        XCTAssertEqual(failed.inUseMemoryBytes, 512)
        XCTAssertEqual(failed.history.samples.map(\.value), [12.5])
        XCTAssertFalse(failed.showsCurve)
    }

    func testStayedFailureBeforeAnySuccessIsTheFailureEmpty() {
        let failed = GPUPageProjection.apply(
            frame: .failed,
            sampledAt: Date(timeIntervalSince1970: 1),
            current: .initial,
            transition: .stayed
        )
        XCTAssertEqual(failed.chrome, .samplingFailure)
        XCTAssertNotEqual(failed.chrome, .skeleton)
        XCTAssertFalse(failed.visitSucceeded)
        XCTAssertNil(failed.utilizationPercent)
        XCTAssertNil(failed.inUseMemoryBytes)
        XCTAssertTrue(failed.history.samples.isEmpty)
    }

    func testSuccessWithMissingKeysStaysDashesThroughALaterFailure() {
        let missing = succeed([node([:])], at: 1)
        XCTAssertEqual(missing.chrome, .readings)
        XCTAssertTrue(missing.visitSucceeded)
        XCTAssertEqual(missing.utilizationText, "—")
        XCTAssertEqual(missing.memoryText, "—")
        XCTAssertTrue(missing.history.samples.isEmpty)

        let failed = GPUPageProjection.apply(
            frame: .failed,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: missing,
            transition: .stayed
        )
        XCTAssertEqual(failed.chrome, .readings)
        XCTAssertNotEqual(failed.chrome, .samplingFailure)
        XCTAssertNotEqual(failed.chrome, .skeleton)
        XCTAssertEqual(failed.utilizationText, "—")
        XCTAssertEqual(failed.memoryText, "—")
        XCTAssertTrue(failed.history.samples.isEmpty)
    }

    func testOneMissingKeyDoesNotHideTheOther() {
        let memoryOnly = succeed([
            node(["In use system memory": .bytes(0)]),
        ], at: 1)
        XCTAssertEqual(memoryOnly.utilizationText, "—")
        XCTAssertEqual(memoryOnly.memoryText, "0 字节")

        let utilOnly = succeed([
            node(["Device Utilization %": .number(0)]),
        ], at: 2)
        XCTAssertEqual(utilOnly.utilizationText, "0.0%")
        XCTAssertEqual(utilOnly.memoryText, "—")
    }

    func testCurveSkipsMissingAndDuplicateTimesAndCapsAtNinety() {
        var page = GPUPageState.initial
        page = succeed([
            node([
                "In use system memory": .bytes(1),
                "Device Utilization %": .number(5),
            ]),
        ], at: 1, current: page)
        page = succeed([
            node(["In use system memory": .bytes(2)]),
        ], at: 2, current: page)
        XCTAssertEqual(page.history.samples.map(\.value), [5])
        XCTAssertEqual(page.inUseMemoryBytes, 2)
        XCTAssertFalse(page.showsCurve)

        page = succeed([
            node(["Device Utilization %": .number(9)]),
        ], at: 1, current: page)
        XCTAssertEqual(page.utilizationPercent, 9)
        XCTAssertEqual(page.history.samples.map(\.value), [5])

        page = succeed([
            node(["Device Utilization %": .number(6)]),
        ], at: 3, current: page)
        XCTAssertEqual(page.history.samples.map(\.value), [5, 6])
        XCTAssertTrue(page.showsCurve)

        page = GPUPageProjection.apply(
            nodes: [node(["Device Utilization %": .number(8)])],
            frame: .succeeded,
            sampledAt: nil,
            current: page,
            transition: .stayed
        )
        XCTAssertEqual(page.utilizationPercent, 8)
        XCTAssertEqual(page.history.samples.map(\.value), [5, 6])

        var capped = GPUPageState.initial
        for index in 0...90 {
            capped = succeed([
                node(["Device Utilization %": .number(Double(index))]),
            ], at: TimeInterval(index + 1), current: capped)
        }
        XCTAssertEqual(capped.history.samples.count, 90)
        XCTAssertEqual(capped.history.samples.first?.value, 1)
        XCTAssertEqual(capped.history.samples.last?.value, 90)
        XCTAssertFalse(capped.history.samples.map(\.value).contains(0))
    }

    func testPendingFirstFrameIsSkeletonAndALaterPendingKeepsReadings() {
        let waiting = GPUPageProjection.apply(
            frame: .pending,
            sampledAt: nil,
            current: .initial,
            transition: .stayed
        )
        XCTAssertEqual(waiting.chrome, .skeleton)
        XCTAssertEqual(waiting.utilizationText, "—")

        let ready = succeed([
            node(["Device Utilization %": .number(3)]),
        ], at: 1)
        let still = GPUPageProjection.apply(
            frame: .pending,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: ready,
            transition: .stayed
        )
        XCTAssertEqual(still.chrome, .readings)
        XCTAssertEqual(still.utilizationPercent, 3)
        XCTAssertEqual(still.history.samples.count, 1)
    }

    func testCopyNamesTheTwoReadingsAndTheExistingFailureChrome() {
        XCTAssertEqual(GPUPageCopy.utilization, "GPU 使用率")
        XCTAssertEqual(GPUPageCopy.memory, "GPU 占用内存")
        XCTAssertEqual(GPUPageCopy.failureTitle, "暂时读不到 GPU 数据")
        XCTAssertEqual(GPUPageCopy.failureMessage, "这轮采样没有回来，点重试再试。")
        XCTAssertEqual(GPUPageCopy.failureMessage, SamplingRetryChrome.overviewFailureMessage)
        XCTAssertEqual(GPUPageProjection.deviceUtilizationKey, "Device Utilization %")
        XCTAssertEqual(GPUPageProjection.inUseSystemMemoryKey, "In use system memory")
        let blob = [
            GPUPageCopy.utilization,
            GPUPageCopy.memory,
            GPUPageCopy.failureTitle,
            GPUPageCopy.sampling,
            GPUPageCopy.chartCollecting,
        ].joined(separator: "\n")
        XCTAssertFalse(blob.contains("显存"))
        XCTAssertFalse(blob.contains("VRAM"))
        XCTAssertFalse(blob.contains("即将推出"))
        XCTAssertFalse(blob.contains("危险"))
        XCTAssertFalse(blob.contains("泄漏"))
    }

    func testEnteringGPUUsesMemoryDescendingAndDoesNotAddASortColumn() {
        XCTAssertEqual(
            ProcessTableSort.defaultSort(for: .gpu),
            ProcessTableSort(column: .memory, descending: true)
        )
        XCTAssertFalse(ProcessColumnTitle.cpuPage.contains("GPU"))
        XCTAssertFalse(ProcessColumnTitle.diskPage.contains("GPU"))
        XCTAssertFalse(ProcessColumnTitle.networkPage.contains("GPU"))
    }

    func succeed(
        _ nodes: [GPUAcceleratorNode],
        at time: TimeInterval,
        current: GPUPageState = .initial,
        transition: GPUPageTransition = .stayed
    ) -> GPUPageState {
        GPUPageProjection.apply(
            nodes: nodes,
            frame: .succeeded,
            sampledAt: Date(timeIntervalSince1970: time),
            current: current,
            transition: transition
        )
    }

    func node(
        _ statistics: [String: GPUStatistic],
        ioReportDevicePercent: Double? = nil
    ) -> GPUAcceleratorNode {
        GPUAcceleratorNode(
            statistics: statistics,
            ioReportDevicePercent: ioReportDevicePercent
        )
    }
}
