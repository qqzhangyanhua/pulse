import XCTest
@testable import SamplingCore

/// GPU power and frequency sparklines. Frames and page changes in; the two series out.
/// A missing reading is not a point. Idle is not 0 Hz. History is not this series.
final class DashboardCoreGPUSparklineTests: XCTestCase {
    func testPowerAndFrequencySparklinesAppendOnlyWhileTheGPUPageIsVisible() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, at: 1_700_000_001, watts: 4.5, frequency: .hertz(2_400_000_000), page: .cpu)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [])
        XCTAssertFalse(core.gpuPage.showsPowerSparkline)
        XCTAssertFalse(core.gpuPage.showsFrequencySparkline)

        _ = core.selectPage(.gpu)
        accept(&core, at: 1_700_000_002, watts: 1.5, frequency: .hertz(1_296_000_000), page: .gpu)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [1.5])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [1_296_000_000])
        XCTAssertFalse(core.gpuPage.showsPowerSparkline)
        XCTAssertFalse(core.gpuPage.showsFrequencySparkline)

        accept(&core, at: 1_700_000_003, watts: 0, frequency: .hertz(0), page: .gpu)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [1.5, 0])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [1_296_000_000, 0])
        XCTAssertTrue(core.gpuPage.showsPowerSparkline)
        XCTAssertTrue(core.gpuPage.showsFrequencySparkline)
    }

    func testLeavingTheGPUPageClearsBothSparklinesAndKeepsTheUtilizationCurve() {
        var core = DashboardCore(ownPid: 1)
        _ = core.selectPage(.gpu)
        accept(&core, at: 1_700_000_010, watts: 1.5, frequency: .hertz(1_296_000_000), page: .gpu, percent: 41)
        accept(&core, at: 1_700_000_011, watts: 2, frequency: .hertz(972_000_000), page: .gpu, percent: 55)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [1.5, 2])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [1_296_000_000, 972_000_000])
        XCTAssertEqual(core.gpuPage.history.samples.map(\.value), [41, 55])

        _ = core.selectPage(.cpu)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [])
        XCTAssertEqual(core.gpuPage.history.samples.map(\.value), [41, 55])

        accept(&core, at: 1_700_000_012, watts: 9, frequency: .hertz(3_000_000_000), page: .cpu, percent: 60)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [])
        XCTAssertEqual(core.gpuPage.history.samples.map(\.value), [41, 55, 60])

        _ = core.selectPage(.gpu)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [])
        accept(&core, at: 1_700_000_013, watts: 0.4, frequency: .hertz(389_000_000), page: .gpu, percent: 12)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [0.4])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [389_000_000])
        XCTAssertEqual(core.gpuPage.history.samples.map(\.value), [41, 55, 60, 12])
    }

    func testMissingReadingsAreNotAppendedAndIdleFrequencyIsNotStoredAsZero() {
        var core = DashboardCore(ownPid: 1)
        _ = core.selectPage(.gpu)
        accept(&core, at: 1_700_000_020, watts: 1.5, frequency: .hertz(1_296_000_000), page: .gpu)
        accept(&core, at: 1_700_000_021, watts: nil, frequency: .missing, page: .gpu)
        accept(&core, at: 1_700_000_022, watts: .nan, frequency: .idle, page: .gpu)
        accept(&core, at: 1_700_000_023, watts: .infinity, frequency: .hertz(.nan), page: .gpu)
        accept(&core, at: 1_700_000_024, watts: -.infinity, frequency: .hertz(-1), page: .gpu)
        accept(&core, at: 1_700_000_020, watts: 8, frequency: .hertz(500_000_000), page: .gpu)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [1.5])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [1_296_000_000])
        XCTAssertFalse(core.gpuPage.powerSparkline.samples.map(\.value).contains(0))
        XCTAssertFalse(core.gpuPage.frequencySparkline.samples.map(\.value).contains(0))

        _ = core.apply(
            result: Result<SampledFrame, ProbeError>.failure(.unavailable),
            accepted: true,
            page: .gpu
        )
        _ = core.apply(
            result: Result<SampledFrame, ProbeError>.success(
                frame(at: 1_700_000_025, watts: 6, frequency: .hertz(778_000_000))
            ),
            accepted: false,
            page: .gpu
        )
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.map(\.value), [1.5])
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.map(\.value), [1_296_000_000])
    }

    func testSparklinesKeepAtMostNinetyPoints() {
        var core = DashboardCore(ownPid: 1)
        _ = core.selectPage(.gpu)
        for index in 0...90 {
            accept(
                &core,
                at: 1_700_000_100 + Double(index),
                watts: Double(index),
                frequency: .hertz(Double(index) * 1_000_000),
                page: .gpu
            )
        }
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.count, 90)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.first?.value, 1)
        XCTAssertEqual(core.gpuPage.powerSparkline.samples.last?.value, 90)
        XCTAssertFalse(core.gpuPage.powerSparkline.samples.map(\.value).contains(0))
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.count, 90)
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.first?.value, 1_000_000)
        XCTAssertEqual(core.gpuPage.frequencySparkline.samples.last?.value, 90_000_000)
        XCTAssertFalse(core.gpuPage.frequencySparkline.samples.map(\.value).contains(0))
    }

    func testHistoryStoreCreateAndInsertSQLHaveNoPowerOrFrequencyColumn() throws {
        let store = try repoText("Pulse/Sampling/HistoryStore.swift")
        let pieces = [
            try XCTUnwrap(sqlSlice(store, from: "CREATE TABLE IF NOT EXISTS sample (", through: ");")),
            try XCTUnwrap(sqlSlice(store, from: "CREATE TABLE IF NOT EXISTS minute (", through: ");")),
            try XCTUnwrap(sqlSlice(store, from: "CREATE TABLE IF NOT EXISTS quarter (", through: ");")),
            try XCTUnwrap(sqlSlice(store, from: "CREATE TABLE IF NOT EXISTS top_process (", through: ");")),
            try XCTUnwrap(sqlSlice(store, from: "CREATE TABLE IF NOT EXISTS event (", through: ");")),
            try XCTUnwrap(sqlSlice(
                store,
                from: "INSERT OR REPLACE INTO",
                through: "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            )),
            try XCTUnwrap(sqlSlice(
                store,
                from: "INSERT INTO top_process",
                through: "primary_value) VALUES (?, ?, ?, ?, ?)"
            )),
            try XCTUnwrap(sqlSlice(store, from: "INSERT INTO event", through: "detail) VALUES (?, ?, ?)")),
        ]
        XCTAssertTrue(pieces[0].contains("disk_write REAL"))
        XCTAssertTrue(pieces[0].contains("gpu REAL"))
        XCTAssertTrue(pieces[5].contains("disk_write, gpu"))
        for sql in pieces {
            let lowered = sql.lowercased()
            XCTAssertFalse(lowered.contains("power"), sql)
            XCTAssertFalse(lowered.contains("frequency"), sql)
            XCTAssertFalse(lowered.contains("watt"), sql)
            XCTAssertFalse(lowered.contains("hertz"), sql)
        }
        let noted = try repoText("Pulse/Models/DashboardCore+History.swift")
        for token in ["gpuWatts", "gpuFrequency", "powerSparkline", "frequencySparkline"] {
            XCTAssertFalse(noted.contains(token), token)
        }
        let policy = try repoText("Pulse/Models/HistoryPolicy.swift")
        XCTAssertFalse(policy.contains("gpuWatts"))
        XCTAssertFalse(policy.contains("gpuFrequency"))
    }

    func testPowerAndFrequencyCardsEmbedTheVisitSparklines() throws {
        let overview = try WiringSourceText.text(for: "GPUOverviewSection")
        XCTAssertEqual(occurrenceCount(of: "SparklineChart(", in: overview), 2)
        XCTAssertTrue(overview.contains("vm.gpuPage.powerSparkline.samples"))
        XCTAssertTrue(overview.contains("vm.gpuPage.frequencySparkline.samples"))
        XCTAssertTrue(overview.contains("vm.gpuPage.showsPowerSparkline"))
        XCTAssertTrue(overview.contains("vm.gpuPage.showsFrequencySparkline"))
        XCTAssertTrue(overview.contains("vm.gpuPage.powerSparklineDomain"))
        XCTAssertTrue(overview.contains("vm.gpuPage.frequencySparklineDomain"))
        XCTAssertTrue(overview.contains("showsAxes: false"))
        XCTAssertEqual(occurrenceCount(of: "HistoryAnnotatedChart", in: overview), 1)
        let readings = try repoText("Pulse/Views/GPUOverviewSection+Readings.swift")
        XCTAssertFalse(readings.contains("?? 0"))
        XCTAssertFalse(readings.contains(".idle"))
        var cursor = readings.startIndex
        for token in [
            "GPUPageCopy.utilization",
            "GPUPageCopy.memory",
            "GPUPageCopy.power",
            "powerSparkline",
            "GPUPageCopy.frequency",
            "frequencySparkline",
        ] {
            guard let found = readings.range(of: token, range: cursor..<readings.endIndex) else {
                return XCTFail(token)
            }
            cursor = found.upperBound
        }
    }

    private func accept(
        _ core: inout DashboardCore,
        at seconds: TimeInterval,
        watts: Double?,
        frequency: GPUFrequency,
        page: DashboardPage,
        percent: Double? = nil
    ) {
        _ = core.apply(
            result: Result<SampledFrame, ProbeError>.success(
                frame(at: seconds, watts: watts, frequency: frequency, percent: percent)
            ),
            accepted: true,
            page: page
        )
    }

    private func frame(
        at seconds: TimeInterval,
        watts: Double?,
        frequency: GPUFrequency,
        percent: Double? = nil
    ) -> SampledFrame {
        let capturedAt = Date(timeIntervalSince1970: seconds)
        let nodes: [GPUAcceleratorNode]? = percent.map { value in
            [GPUAcceleratorNode(statistics: [
                GPUPageProjection.deviceUtilizationKey: .number(value),
                GPUPageProjection.inUseSystemMemoryKey: .bytes(8_192),
            ])]
        }
        return SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 100,
                totalBytes: 1_000,
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
            systemCpuPercent: nil,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            gpuNodes: nodes,
            cpuEnergy: EnergyModelReading(gpuWatts: watts, gpuFrequency: frequency)
        )
    }

    private func repoText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func sqlSlice(_ source: String, from start: String, through end: String) -> String? {
        guard let open = source.range(of: start),
              let close = source.range(of: end, range: open.lowerBound..<source.endIndex) else { return nil }
        return String(source[open.lowerBound..<close.upperBound])
    }
}

private enum ProbeError: Error {
    case unavailable
}
