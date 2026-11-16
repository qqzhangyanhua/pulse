import XCTest
@testable import SamplingCore

/// `GPUState` through its own interface. Which page records what, leave rules, and the failure path.
final class GPUStateTests: XCTestCase {
    func testOffPageFrameRecordsUtilizationAlertAndTimeButNotPageOnlyReadings() {
        var gpu = GPUState(ownPid: 1)
        gpu.absorb(input(at: 100, percent: 41), page: .memory)

        XCTAssertEqual(gpu.page.utilizationPercent, 41)
        XCTAssertEqual(gpu.page.history.samples.map(\.value), [41])
        XCTAssertEqual(gpu.alertUtilizationPercent, 41)
        XCTAssertNotNil(gpu.time)
        XCTAssertNil(gpu.share)
        XCTAssertEqual(gpu.frequencyDistribution, .missing)
        XCTAssertNil(gpu.watts)
        XCTAssertEqual(gpu.frequency, .missing)
        XCTAssertEqual(gpu.powerText, "—")
        XCTAssertTrue(gpu.page.powerSparkline.samples.isEmpty)
        XCTAssertTrue(gpu.page.frequencySparkline.samples.isEmpty)
    }

    func testGPUPageFrameFeedsCardValueAndSparklineFromTheSameReading() {
        var gpu = GPUState(ownPid: 1)
        gpu.absorb(input(at: 100, percent: 41), page: .gpu)

        XCTAssertEqual(gpu.watts, 3)
        XCTAssertEqual(gpu.frequency, .hertz(1_296_000_000))
        XCTAssertEqual(gpu.powerText, "3.0 W")
        XCTAssertEqual(gpu.frequencyText, "1.30 GHz")
        XCTAssertEqual(gpu.powerLine, "GPU 功耗 · 3.0 W")
        XCTAssertEqual(gpu.frequencyLine, "GPU 频率 · 1.30 GHz")
        XCTAssertEqual(gpu.page.powerSparkline.samples.map(\.value), [3])
        XCTAssertEqual(gpu.page.frequencySparkline.samples.map(\.value), [1_296_000_000])
        XCTAssertEqual(gpu.frequencyDistribution, Self.bars)
        XCTAssertEqual(gpu.share, .missing)
    }

    func testMissingEnergyOnTheGPUPageIsADashNotZero() {
        var gpu = GPUState(ownPid: 1)
        gpu.absorb(input(at: 100, percent: 41, energy: nil), page: .gpu)

        XCTAssertNil(gpu.watts)
        XCTAssertEqual(gpu.frequency, .missing)
        XCTAssertEqual(gpu.powerText, "—")
        XCTAssertEqual(gpu.frequencyText, "—")
        XCTAssertEqual(gpu.frequencyDistribution, .missing)
        XCTAssertTrue(gpu.page.powerSparkline.samples.isEmpty)
    }

    func testLeavingClearsPowerAndFrequencyButKeepsUtilizationShareAndDistribution() {
        var gpu = GPUState(ownPid: 1)
        gpu.absorb(input(at: 100, percent: 41), page: .gpu)
        gpu.transition(from: .gpu, to: .cpu, samplingFailed: false)

        XCTAssertNil(gpu.watts)
        XCTAssertEqual(gpu.frequency, .missing)
        XCTAssertEqual(gpu.powerText, "—")
        XCTAssertTrue(gpu.page.powerSparkline.samples.isEmpty)
        XCTAssertTrue(gpu.page.frequencySparkline.samples.isEmpty)
        XCTAssertEqual(gpu.page.utilizationPercent, 41)
        XCTAssertEqual(gpu.page.history.samples.map(\.value), [41])
        XCTAssertEqual(gpu.share, .missing)
        XCTAssertEqual(gpu.frequencyDistribution, Self.bars)

        gpu.absorb(input(at: 101, percent: 55), page: .cpu)
        XCTAssertNil(gpu.watts)
        XCTAssertEqual(gpu.page.history.samples.map(\.value), [41, 55])
    }

    func testSamePageTransitionWritesNothing() {
        var gpu = GPUState(ownPid: 1)
        gpu.absorb(input(at: 100, percent: 41), page: .gpu)
        let before = gpu
        gpu.transition(from: .gpu, to: .gpu, samplingFailed: true)
        XCTAssertEqual(gpu, before)
    }

    func testFrameWithoutGPUNodesClearsTheAlertAndLeavesThePage() {
        var gpu = GPUState(ownPid: 1)
        gpu.absorb(input(at: 100, percent: 41), page: .memory)
        var noRead = input(at: 101, percent: 41)
        noRead.nodes = nil
        gpu.absorb(noRead, page: .memory)

        XCTAssertNil(gpu.alertUtilizationPercent)
        XCTAssertEqual(gpu.page.utilizationPercent, 41)
        XCTAssertEqual(gpu.page.history.samples.map(\.value), [41])
    }

    func testFailureClearsTheAlertAndShowsTheFailureStateOnlyBeforeAFirstSuccess() {
        var gpu = GPUState(ownPid: 1)
        gpu.absorbFailure()
        XCTAssertEqual(gpu.page.chrome, .samplingFailure)
        XCTAssertNil(gpu.alertUtilizationPercent)

        gpu.absorb(input(at: 100, percent: 41), page: .memory)
        XCTAssertEqual(gpu.page.chrome, .readings)
        gpu.absorbFailure()
        XCTAssertEqual(gpu.page.chrome, .readings)
        XCTAssertEqual(gpu.page.utilizationPercent, 41)
        XCTAssertNil(gpu.alertUtilizationPercent)
    }

    func testEnteringWhileSamplingFailedShowsTheFailureStateOtherwiseTheSkeleton() {
        var failed = GPUState(ownPid: 1)
        failed.transition(from: .memory, to: .gpu, samplingFailed: true)
        XCTAssertEqual(failed.page.chrome, .samplingFailure)

        var pending = GPUState(ownPid: 1)
        pending.transition(from: .memory, to: .gpu, samplingFailed: false)
        XCTAssertEqual(pending.page.chrome, .skeleton)
    }

    private static let bars = GPUFrequencyDistribution.bars([
        GPUFrequencyDistributionBar(id: 0, label: "关闭", percentText: "40.0%", fraction: 0.4),
        GPUFrequencyDistributionBar(id: 1, label: "1296 MHz", percentText: "60.0%", fraction: 0.6),
    ])

    private func input(
        at seconds: TimeInterval,
        percent: Double,
        energy: EnergyModelReading? = EnergyModelReading(
            gpuWatts: 3,
            gpuFrequency: .hertz(1_296_000_000),
            gpuFrequencyDistribution: GPUStateTests.bars
        )
    ) -> GPUFrameInput {
        GPUFrameInput(
            nodes: [GPUAcceleratorNode(statistics: [GPUPageProjection.deviceUtilizationKey: .number(percent)])],
            recommendedMaxWorkingSetBytes: nil,
            energy: energy,
            shareClients: [],
            rows: [],
            processListFailed: false,
            sampledAt: Date(timeIntervalSince1970: seconds)
        )
    }
}
