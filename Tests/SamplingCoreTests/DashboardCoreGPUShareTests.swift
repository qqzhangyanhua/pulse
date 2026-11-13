import XCTest
@testable import SamplingCore

/// GPU share ranking on DashboardCore. Frames in, the top-5 card out.
final class DashboardCoreGPUShareTests: XCTestCase {
    func testGPUPageChoosesFiveAndKeepsPulse() {
        var core = DashboardCore(ownPid: 42)
        let ranked: [(UInt64, Int32, UInt64, String)] = [
            (1, 7, 900_000_000, "Seven"),
            (2, 42, 800_000_000, "Mail"),
            (3, 5, 700_000_000, "Five"),
            (4, 4, 600_000_000, "Four"),
            (5, 3, 500_000_000, "Three"),
            (6, 2, 400_000_000, "Two"),
            (7, 9, 100_000_000, "Nine"),
        ]
        _ = core.apply(result: success(frame(at: 1_000, samples: ranked.map { ($0.0, $0.1, UInt64(0), $0.3) })), accepted: true, page: .gpu)
        _ = core.apply(result: success(frame(at: 1_001, samples: ranked)), accepted: true, page: .gpu)

        guard case .rows(let rows) = core.gpuShare else {
            return XCTFail("expected five rows, got \(String(describing: core.gpuShare))")
        }
        XCTAssertEqual(rows.map(\.pid), [7, 42, 5, 4, 3])
        XCTAssertEqual(rows.map(\.name), ["Seven", "Pulse", "Five", "Four", "Three"])
        XCTAssertEqual(rows.map(\.shareText), ["90.0%", "80.0%", "70.0%", "60.0%", "50.0%"])
        XCTAssertFalse(rows.contains { $0.pid == 2 || $0.pid == 9 })
    }

    func testShareIsNotRankedOffTheGPUPage() {
        var core = DashboardCore(ownPid: 1)
        _ = core.apply(result: success(frame(at: 900, samples: [(1, 10, 9_000_000_000, "Safari")])), accepted: true, page: .memory)
        XCTAssertNil(core.gpuShare)
        XCTAssertEqual(core.gpuPage.utilizationPercent, 41)

        _ = core.apply(result: success(frame(at: 1_000, samples: [(1, 10, 0, "Safari")])), accepted: true, page: .gpu)
        _ = core.apply(result: success(frame(at: 1_001, samples: [(1, 10, 500_000_000, "Safari")])), accepted: true, page: .gpu)
        XCTAssertEqual(shareTexts(core), ["50.0%"])

        _ = core.apply(result: success(frame(at: 1_002, samples: [(1, 10, 10_000_000_000, "Safari")])), accepted: true, page: .memory)
        XCTAssertEqual(shareTexts(core), ["50.0%"])
        XCTAssertEqual(core.gpuPage.history.samples.map(\.value), [41, 41, 41, 41])

        _ = core.apply(result: success(frame(at: 1_003, samples: [(1, 10, 600_000_000, "Safari")])), accepted: true, page: .gpu)
        XCTAssertEqual(shareTexts(core), ["5.0%"])
        XCTAssertEqual(named(core), ["Safari"])
    }

    func testCounterRewindPublishesOneDashRowNotAMissingCard() {
        var core = DashboardCore(ownPid: 1)
        _ = core.apply(result: success(frame(at: 1_000, samples: [(1, 8, 2_000_000_000, "Preview")])), accepted: true, page: .gpu)
        _ = core.apply(result: success(frame(at: 1_001, samples: [(1, 8, 1_000_000_000, "Preview")])), accepted: true, page: .gpu)

        guard case .rows(let rows) = core.gpuShare else {
            return XCTFail("expected one dash row, got \(String(describing: core.gpuShare))")
        }
        XCTAssertNotEqual(core.gpuShare, .missing)
        XCTAssertEqual(rows.map(\.pid), [8])
        XCTAssertEqual(rows.map(\.shareText), ["—"])
        XCTAssertNil(rows[0].percent)
    }

    func testNilSharesSortAfterNumbersAndStayInsideFive() {
        var core = DashboardCore(ownPid: 1)
        let baseline: [(UInt64, Int32, UInt64, String)] = [
            (1, 1, 0, "High"),
            (2, 2, 0, "Mid"),
            (3, 4, 0, "Low"),
            (4, 6, 0, "Lower"),
            (5, 8, 2_000_000_000, "Rewind"),
            (6, 9, 0, "Gone"),
            (7, 9, 0, "Gone"),
        ]
        let current: [(UInt64, Int32, UInt64, String)] = [
            (1, 1, 900_000_000, "High"),
            (2, 2, 700_000_000, "Mid"),
            (3, 4, 600_000_000, "Low"),
            (4, 6, 400_000_000, "Lower"),
            (5, 8, 1_000_000_000, "Rewind"),
            (6, 9, 500_000_000, "Gone"),
        ]
        _ = core.apply(result: success(frame(at: 1_000, samples: baseline)), accepted: true, page: .gpu)
        _ = core.apply(result: success(frame(at: 1_001, samples: current)), accepted: true, page: .gpu)

        guard case .rows(let rows) = core.gpuShare else {
            return XCTFail("expected ranked rows, got \(String(describing: core.gpuShare))")
        }
        XCTAssertEqual(rows.map(\.pid), [1, 2, 4, 6, 8])
        XCTAssertEqual(rows.map(\.shareText), ["90.0%", "70.0%", "60.0%", "40.0%", "—"])
        XCTAssertFalse(rows.contains { $0.pid == 9 })
    }

    func testShareOverOneHundredStaysRanked() {
        var core = DashboardCore(ownPid: 1)
        _ = core.apply(result: success(frame(at: 1_000, samples: [(1, 4, 0, "FinalCut")])), accepted: true, page: .gpu)
        _ = core.apply(result: success(frame(at: 1_001, samples: [(1, 4, 2_500_000_000, "FinalCut")])), accepted: true, page: .gpu)
        XCTAssertEqual(shareTexts(core), ["250.0%"])
        XCTAssertNotEqual(core.gpuShare, .missing)
    }

    func testNoAGXClientsAreAMissingCardNotZeros() {
        var core = DashboardCore(ownPid: 1)
        _ = core.apply(result: success(frame(at: 1_000, samples: [])), accepted: true, page: .gpu)

        XCTAssertEqual(core.gpuShare, .missing)
        XCTAssertEqual(core.gpuPage.utilizationPercent, 41)
    }

    private func success(_ frame: SampledFrame) -> Result<SampledFrame, GPUShareDeliveryError> {
        .success(frame)
    }

    private func shareTexts(_ core: DashboardCore) -> [String] {
        guard case .rows(let rows) = core.gpuShare else { return [] }
        return rows.map(\.shareText)
    }

    private func named(_ core: DashboardCore) -> [String] {
        guard case .rows(let rows) = core.gpuShare else { return [] }
        return rows.map(\.name)
    }

    private func frame(
        at time: TimeInterval,
        samples: [(UInt64, Int32, UInt64, String)]
    ) -> SampledFrame {
        let capturedAt = Date(timeIntervalSince1970: time)
        let rows = samples.map { sample in
            ProcessRow(
                pid: sample.1,
                name: sample.3,
                bundleIdentifier: "app.\(sample.1)",
                executablePath: "/Apps/\(sample.3)",
                cpuPercent: 1,
                memoryBytes: 100,
                threadCount: 1
            )
        }
        let clients = samples.map { sample in
            GPUShareClientSample(
                id: sample.0,
                pid: sample.1,
                creatorName: sample.3,
                accumulatedGPUTimeNanoseconds: sample.2
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

private enum GPUShareDeliveryError: Error {
    case unavailable
}
