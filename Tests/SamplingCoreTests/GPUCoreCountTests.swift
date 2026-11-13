import XCTest
@testable import SamplingCore

/// GPU core count is a registry reading on the GPU page, not a second utilization.
final class GPUCoreCountTests: XCTestCase {
    func testParseKeepsAPositiveWholeCountAndDropsTheRest() {
        XCTAssertEqual(GPUCoreCount.registryKey, "gpu-core-count")
        XCTAssertEqual(GPUCoreCount.parse(14), 14)
        XCTAssertEqual(GPUCoreCount.parse(14.0), 14)
        XCTAssertNil(GPUCoreCount.parse(nil))
        XCTAssertNil(GPUCoreCount.parse(0))
        XCTAssertNil(GPUCoreCount.parse(-3))
        XCTAssertNil(GPUCoreCount.parse(14.5))
        XCTAssertNil(GPUCoreCount.parse(.nan))
        XCTAssertNil(GPUCoreCount.parse(.infinity))
    }

    func testReadingsShowTheFirstPositiveCoreCountAndHideWhenMissing() {
        let shown = succeed([
            node([
                "In use system memory": .bytes(40),
                "Device Utilization %": .number(12),
            ], coreCount: 8),
            node([
                "Device Utilization %": .number(40),
            ], coreCount: 14),
        ], at: 1)
        XCTAssertEqual(shown.coreCountText, "8 核 GPU")
        XCTAssertNotEqual(shown.coreCountText, "22 核 GPU")
        XCTAssertEqual(shown.utilizationPercent, 12)
        XCTAssertEqual(shown.inUseMemoryBytes, 40)
        XCTAssertEqual(shown.history.samples.map(\.value), [12])

        let later = succeed([
            node(["Device Utilization %": .number(3)]),
            node(["Device Utilization %": .number(4)], coreCount: 10),
        ], at: 2)
        XCTAssertEqual(later.coreCountText, "10 核 GPU")
        XCTAssertEqual(later.utilizationPercent, 3)

        let hidden = succeed([
            node(["Device Utilization %": .number(1)]),
        ], at: 3)
        XCTAssertNil(hidden.coreCountText)
        XCTAssertEqual(hidden.utilizationText, "1.0%")

        let zero = succeed([
            node(["Device Utilization %": .number(1)], coreCount: 0),
        ], at: 4)
        XCTAssertNil(zero.coreCountText)

        let negative = succeed([
            node(["Device Utilization %": .number(1)], coreCount: -2),
        ], at: 5)
        XCTAssertNil(negative.coreCountText)
    }

    func testCoreCountSurvivesLeaveAndALaterMissHidesItWithoutZeroingTheCurve() {
        let current = succeed([
            node([
                "In use system memory": .bytes(8),
                "Device Utilization %": .number(10),
            ], coreCount: 14),
        ], at: 1)
        XCTAssertEqual(current.coreCountText, "14 核 GPU")

        let left = GPUPageProjection.apply(
            nodes: [node(["Device Utilization %": .number(80)], coreCount: 99)],
            frame: .succeeded,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: current,
            transition: .justLeft
        )
        XCTAssertEqual(left.coreCountText, "14 核 GPU")
        XCTAssertEqual(left.utilizationPercent, 10)
        XCTAssertEqual(left.history.samples.map(\.value), [10])

        let entered = GPUPageProjection.apply(
            frame: .pending,
            sampledAt: nil,
            current: current,
            transition: .justEntered
        )
        XCTAssertEqual(entered.coreCountText, "14 核 GPU")
        XCTAssertEqual(entered.history.samples.map(\.value), [10])
        XCTAssertEqual(entered.chrome, .readings)

        let cleared = succeed([
            node(["Device Utilization %": .number(11)]),
        ], at: 3, current: current)
        XCTAssertNil(cleared.coreCountText)
        XCTAssertEqual(cleared.history.samples.map(\.value), [10, 11])
        XCTAssertFalse(cleared.history.samples.map(\.value).contains(0))
    }

    func testCopyIsTheCoreCountLineAndStaysCalm() {
        XCTAssertEqual(GPUPageCopy.coreCountLine(14), "14 核 GPU")
        let line = GPUPageCopy.coreCountLine(14)
        for forbidden in ["显存", "VRAM", "危险", "泄漏", "核心温度"] {
            XCTAssertFalse(line.contains(forbidden), forbidden)
        }
    }

    func testCoreCountRidesFramesOnOtherPagesAndHidesWhenTheReadDropsIt() {
        var core = DashboardCore(ownPid: 1)
        _ = core.apply(
            result: success(frame(percent: 6, coreCount: 14, at: 1_700_000_010)),
            accepted: true,
            page: .cpu
        )
        XCTAssertEqual(core.gpuPage.coreCountText, "14 核 GPU")
        XCTAssertEqual(core.gpuPage.history.samples.map(\.value), [6])

        _ = core.selectPage(.gpu)
        XCTAssertEqual(core.gpuPage.coreCountText, "14 核 GPU")
        XCTAssertEqual(core.gpuPage.history.samples.map(\.value), [6])
        XCTAssertEqual(core.gpuPage.chrome, .readings)

        _ = core.apply(
            result: success(frame(percent: 7, coreCount: nil, at: 1_700_000_011)),
            accepted: true,
            page: .memory
        )
        XCTAssertNil(core.gpuPage.coreCountText)
        XCTAssertEqual(core.gpuPage.history.samples.map(\.value), [6, 7])
        XCTAssertEqual(core.chipTemperature, .initial)
    }

    private func succeed(
        _ nodes: [GPUAcceleratorNode],
        at time: TimeInterval,
        current: GPUPageState = .initial
    ) -> GPUPageState {
        GPUPageProjection.apply(
            nodes: nodes,
            frame: .succeeded,
            sampledAt: Date(timeIntervalSince1970: time),
            current: current,
            transition: .stayed
        )
    }

    private func node(
        _ statistics: [String: GPUStatistic],
        coreCount: Int? = nil
    ) -> GPUAcceleratorNode {
        GPUAcceleratorNode(statistics: statistics, coreCount: coreCount)
    }

    private func success(_ frame: SampledFrame) -> Result<SampledFrame, GPUCoreCountDeliveryError> {
        .success(frame)
    }

    private func frame(percent: Double, coreCount: Int?, at time: TimeInterval) -> SampledFrame {
        let capturedAt = Date(timeIntervalSince1970: time)
        return SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 1_000,
                totalBytes: 4_000,
                breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
                pressure: .normal,
                pressureMetric: 0.1,
                pressureSeries: [],
                capturedAt: capturedAt,
                swapUsedBytes: nil
            ),
            rows: [],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 1,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            gpuNodes: [node([
                "Device Utilization %": .number(percent),
            ], coreCount: coreCount)]
        )
    }
}

private enum GPUCoreCountDeliveryError: Error {
    case unavailable
}
