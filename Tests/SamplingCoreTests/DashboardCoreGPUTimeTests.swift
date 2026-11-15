import XCTest
@testable import SamplingCore

/// GPU time ranking on DashboardCore. Frames in, the top-5 card out.
final class DashboardCoreGPUTimeTests: XCTestCase {
    func testGPUTimeAccumulatesWhileAnotherPageIsSelected() {
        var core = DashboardCore(ownPid: 42)
        _ = core.apply(
            result: success(frame(at: 1_000, samples: [(1, 10, 100, 0, "Safari")])),
            accepted: true,
            page: .memory
        )
        _ = core.apply(
            result: success(frame(at: 1_001, samples: [(1, 10, 100, 1_500_000_000, "Safari")])),
            accepted: true,
            page: .cpu
        )

        XCTAssertNil(core.gpuShare)
        XCTAssertEqual(core.gpuTime?.rows.map(\.name), ["Safari"])
        XCTAssertEqual(core.gpuTime?.rows.map(\.secondsText), ["1.5 秒"])
        XCTAssertEqual(core.gpuTime?.rows.map(\.exited), [false])

        _ = core.apply(
            result: success(frame(at: 1_002, samples: [(1, 10, 100, 2_500_000_000, "Safari")])),
            accepted: true,
            page: .network
        )
        XCTAssertNil(core.gpuShare)
        XCTAssertEqual(core.gpuTime?.rows.map(\.secondsText), ["2.5 秒"])
        XCTAssertNotEqual(core.gpuTime?.rows.map(\.secondsText), ["1.5 秒"])
        XCTAssertNotEqual(core.gpuTime?.rows.first?.secondsText, "0.0 秒")
    }

    func testGPUTimeTopFivePutsTheSmallerPidFirstOnATie() {
        var core = DashboardCore(ownPid: 42)
        let ranked: [(UInt64, Int32, UInt64, UInt64, String)] = [
            (1, 4, 11, 9_000_000_000, "Four"),
            (2, 5, 12, 8_000_000_000, "Five"),
            (3, 42, 13, 8_000_000_000, "Mail"),
            (4, 6, 14, 7_000_000_000, "Six"),
            (5, 11, 15, 6_000_000_000, "Eleven"),
            (6, 12, 16, 1_000_000_000, "Twelve"),
        ]
        _ = core.apply(
            result: success(frame(at: 2_000, samples: ranked.map { ($0.0, $0.1, $0.2, UInt64(0), $0.4) })),
            accepted: true,
            page: .disk
        )
        _ = core.apply(result: success(frame(at: 2_001, samples: ranked)), accepted: true, page: .energy)

        XCTAssertEqual(core.gpuTime?.rows.map(\.pid), [4, 5, 42, 6, 11])
        XCTAssertEqual(core.gpuTime?.rows.map(\.name), ["Four", "Five", "Pulse", "Six", "Eleven"])
        XCTAssertEqual(
            core.gpuTime?.rows.map(\.secondsText),
            ["9.0 秒", "8.0 秒", "8.0 秒", "7.0 秒", "6.0 秒"]
        )
        XCTAssertFalse(core.gpuTime?.rows.contains { $0.pid == 12 } ?? true)
        XCTAssertNil(core.gpuShare)
    }

    private func success(_ frame: SampledFrame) -> Result<SampledFrame, GPUTimeDeliveryError> {
        .success(frame)
    }

    private func frame(
        at time: TimeInterval,
        samples: [(UInt64, Int32, UInt64, UInt64, String)]
    ) -> SampledFrame {
        let capturedAt = Date(timeIntervalSince1970: time)
        let rows = samples.map { sample in
            ProcessRow(
                pid: sample.1,
                name: sample.4,
                bundleIdentifier: "app.\(sample.1)",
                executablePath: "/Apps/\(sample.4)",
                cpuPercent: 1,
                memoryBytes: 100,
                threadCount: 1,
                startTimeSeconds: sample.2
            )
        }
        let clients = samples.map { sample in
            GPUShareClientSample(
                id: sample.0,
                pid: sample.1,
                creatorName: sample.4,
                accumulatedGPUTimeNanoseconds: sample.3
            )
        }
        return SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 1_000,
                totalBytes: 2_000,
                breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
                pressure: .normal,
                pressureMetric: 0,
                pressureSeries: [],
                capturedAt: capturedAt,
                swapUsedBytes: 0
            ),
            rows: rows,
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 10,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            gpuNodes: [
                GPUAcceleratorNode(statistics: [
                    GPUPageProjection.deviceUtilizationKey: .number(41),
                    GPUPageProjection.inUseSystemMemoryKey: .bytes(8_192),
                ]),
            ],
            gpuShareClients: clients
        )
    }
}

private enum GPUTimeDeliveryError: Error {
    case unavailable
}
