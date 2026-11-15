import XCTest
@testable import SamplingCore

/// Frequency-distribution card on DashboardCore. Frames and page switches in, the card out.
final class DashboardCoreGPUDistributionTests: XCTestCase {
    func testLeavingTheGPUPageDoesNotUpdateFrequencyDistribution() {
        var core = DashboardCore(ownPid: 1)
        var first = EnergyModelReading()
        first.gpuFrequency = .hertz(559_000_000)
        first.gpuFrequencyDistribution = GPUFrequencyDistribution.bars([
            GPUFrequencyDistributionBar(id: 0, label: "关闭", percentText: "33.3%", fraction: 1.0 / 3.0),
            GPUFrequencyDistributionBar(id: 1, label: "486 MHz", percentText: "66.7%", fraction: 2.0 / 3.0),
        ])
        _ = core.apply(result: success(frame(reading: first)), accepted: true, page: .gpu)
        XCTAssertEqual(core.cpuEnergy?.gpuFrequency, .hertz(559_000_000))
        XCTAssertEqual(labels(core), ["关闭", "486 MHz"])
        XCTAssertEqual(percents(core), ["33.3%", "66.7%"])

        var later = EnergyModelReading()
        later.gpuFrequency = .idle
        later.gpuFrequencyDistribution = .bars([
            GPUFrequencyDistributionBar(id: 0, label: "关闭", percentText: "100.0%", fraction: 1),
        ])
        _ = core.apply(result: success(frame(reading: later)), accepted: true, page: .memory)
        XCTAssertEqual(labels(core), ["关闭", "486 MHz"])
        XCTAssertEqual(percents(core), ["33.3%", "66.7%"])

        _ = core.apply(result: success(frame(reading: nil)), accepted: true, page: .cpu)
        XCTAssertEqual(labels(core), ["关闭", "486 MHz"])
        XCTAssertEqual(percents(core), ["33.3%", "66.7%"])
    }

    func testFrequencyDistributionWithoutASampleDeltaIsADash() {
        var core = DashboardCore(ownPid: 1)
        _ = core.apply(result: success(frame(reading: nil)), accepted: true, page: .gpu)
        XCTAssertEqual(core.gpuFrequencyDistribution, .missing)
        XCTAssertEqual(GPUFrequencyDistributionCopy.missing, "—")

        var seen = EnergyModelReading()
        seen.gpuFrequencyDistribution = .bars([
            GPUFrequencyDistributionBar(id: 0, label: "P1", percentText: "100.0%", fraction: 1),
        ])
        _ = core.apply(result: success(frame(reading: seen)), accepted: true, page: .gpu)
        XCTAssertEqual(labels(core), ["P1"])

        var quiet = EnergyModelReading()
        quiet.gpuFrequency = .missing
        quiet.gpuFrequencyDistribution = .missing
        _ = core.apply(result: success(frame(reading: quiet)), accepted: true, page: .gpu)
        XCTAssertEqual(core.gpuFrequencyDistribution, .missing)
        XCTAssertNotEqual(core.gpuFrequencyDistribution, seen.gpuFrequencyDistribution)
    }

    private func success(_ frame: SampledFrame) -> Result<SampledFrame, GPUDistributionDeliveryError> {
        .success(frame)
    }

    private func labels(_ core: DashboardCore) -> [String] {
        guard case .bars(let bars) = core.gpuFrequencyDistribution else { return [] }
        return bars.map(\.label)
    }

    private func percents(_ core: DashboardCore) -> [String] {
        guard case .bars(let bars) = core.gpuFrequencyDistribution else { return [] }
        return bars.map(\.percentText)
    }

    private func frame(reading: EnergyModelReading?) -> SampledFrame {
        SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 1_000,
                totalBytes: 2_000,
                breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
                pressure: .normal,
                pressureMetric: 0,
                pressureSeries: [],
                capturedAt: Date(timeIntervalSince1970: 1_000),
                swapUsedBytes: 0
            ),
            rows: [],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 10,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            cpuEnergy: reading
        )
    }
}

private enum GPUDistributionDeliveryError: Error {
    case unavailable
}
