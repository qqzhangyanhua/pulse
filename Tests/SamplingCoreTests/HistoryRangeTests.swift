import XCTest
@testable import SamplingCore

final class HistoryRangeTests: XCTestCase {
    func testDefaultRangeIsLive() {
        let core = DashboardCore(ownPid: 1)
        XCTAssertEqual(core.historyCurveRange, .live)
        XCTAssertEqual(HistoryCurveRange.live.title, "实时")
        XCTAssertEqual(HistoryCurveRange.hour.title, "1 小时")
        XCTAssertEqual(HistoryCurveRange.day.title, "24 小时")
        XCTAssertEqual(HistoryCurveRange.week.title, "7 天")
    }

    func testChoosingAnHourSticksUntilThePageChanges() {
        var core = DashboardCore(ownPid: 1)
        _ = core.setHistoryCurveRange(.hour)
        XCTAssertEqual(core.historyCurveRange, .hour)
        _ = core.selectPage(.cpu)
        XCTAssertEqual(core.historyCurveRange, .live)
        _ = core.setHistoryCurveRange(.week)
        _ = core.focusMemoryPage()
        XCTAssertEqual(core.historyCurveRange, .live)
    }

    func testNilSampleIsNotZeroAndAHoleIsNotFilled() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let missing = sample(at: start, cpu: nil)
        let raw = HistoryCurveSeries.raw(samples: [missing], from: start, to: start, value: \.cpuPercent)
        XCTAssertEqual(raw.map(\.value), [nil])
        XCTAssertFalse(raw.contains { $0.value == 0 })

        let later = sample(at: start.addingTimeInterval(30), cpu: 12)
        let holed = HistoryCurveSeries.raw(
            samples: [sample(at: start, cpu: 4), later],
            from: start,
            to: later.at,
            value: \.cpuPercent
        )
        XCTAssertEqual(holed.map(\.value), [4, nil, 12])
    }

    func testMissingMinuteBucketStaysNil() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = HistoryCurveSeries.buckets(
            samples: [
                sample(at: start, cpu: 10),
                sample(at: start.addingTimeInterval(120), cpu: nil),
            ],
            from: start,
            to: start.addingTimeInterval(120),
            step: 60,
            value: \.cpuPercent
        )
        XCTAssertEqual(points.map(\.value), [10, nil, nil])
        XCTAssertFalse(points.contains { $0.value == 0 })
    }

    func testLiveRangeDoesNotClearTheInMemoryRing() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, at: Date(timeIntervalSince1970: 1_700_000_000))
        let count = core.usageHistory.samples.count
        XCTAssertGreaterThan(count, 0)
        _ = core.setHistoryCurveRange(.hour)
        _ = core.setHistoryCurveRange(.live)
        XCTAssertEqual(core.usageHistory.samples.count, count)
    }

    func testEventMarksUseTheGlossaryLabels() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let marks = HistoryCurveSeries.marks([
            HistoryStoredEvent(at: at, event: .sleep),
            HistoryStoredEvent(at: at, event: .wake),
            HistoryStoredEvent(at: at, event: .thermal("serious")),
            HistoryStoredEvent(at: at, event: .pressure("elevated")),
        ])
        XCTAssertEqual(marks.map(\.label), ["睡眠", "唤醒", "热状态", "压力"])
    }

    func testNonLivePlotBreaksOnNilAndKeepsMarks() throws {
        var core = DashboardCore(ownPid: 1)
        let end = Date(timeIntervalSince1970: 1_700_003_600)
        let start = end.addingTimeInterval(-30)
        _ = core.setHistoryCurveRange(.hour)
        _ = core.replaceHistoryCurve(
            samples: [sample(at: start, cpu: 8), sample(at: end, cpu: nil)],
            events: [HistoryStoredEvent(at: start, event: .wake)],
            end: end
        )
        let plot = try XCTUnwrap(core.historyCurvePlot(\.cpuPercent))
        XCTAssertTrue(plot.points.contains { $0.value == nil })
        XCTAssertFalse(plot.points.contains { $0.value == 0 })
        XCTAssertEqual(plot.marks.map(\.label), ["唤醒"])
        _ = core.setHistoryCurveRange(.live)
        XCTAssertNil(core.historyCurvePlot(\.cpuPercent))
    }

    func testRangeControlIsOnTheFivePagesAndNotOnTheMenuBarOrEnergyChart() throws {
        for name in [
            "Pulse/Views/OverviewSection.swift",
            "Pulse/Views/CPUOverviewSection.swift",
            "Pulse/Views/NetworkOverviewSection.swift",
            "Pulse/Views/DiskOverviewSection.swift",
            "Pulse/Views/GPUOverviewSection.swift",
        ] {
            let source = try repoText(name)
            XCTAssertTrue(source.contains("HistoryRangeControl("), name)
        }
        let control = try repoText("Pulse/Views/HistoryRangeControl.swift")
        XCTAssertTrue(control.contains("accessibilityLabel(\"曲线范围\")"))
        XCTAssertTrue(control.contains("reduceMotion ? nil : PulseMotion.page"))
        XCTAssertTrue(control.contains(".accessibilityLabel(mark.label)"))
        XCTAssertFalse(control.contains("HistoryCurvePresentation.unavailable"))
        XCTAssertFalse(try repoText("Pulse/MenuBar/MenuBarPopoverView.swift").contains("HistoryRangeControl"))
        XCTAssertFalse(try repoText("Pulse/Views/EnergyHistoryChart.swift").contains("HistoryRangeControl"))
        XCTAssertFalse(try repoText("Pulse/Views/MachineOverviewSection.swift").contains("HistoryRangeControl"))
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("Models/HistoryCurveRange.swift"))
        XCTAssertTrue(package.contains("Models/DashboardCore+HistoryRange.swift"))
        XCTAssertFalse(package.contains("HistoryRangeControl.swift"))
        let store = try repoText("Pulse/Sampling/HistoryStore.swift")
        XCTAssertTrue(store.contains("func datedEvents(from "))
        XCTAssertTrue(store.contains("func samples(from "))
        XCTAssertTrue(store.contains("func minuteSamples(from "))
        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM+HistoryRange.swift")
        XCTAssertFalse(vm.contains("record(nil)"))
        XCTAssertTrue(vm.contains("minuteSamples(from:"))
        let selection = try repoText("Pulse/Models/DashboardCore+Selection.swift")
        XCTAssertTrue(selection.contains("historyCurveRange = .live"))
    }

    private func accept(_ core: inout DashboardCore, at date: Date) {
        let frame = SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 100,
                totalBytes: 1_000,
                breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
                pressure: .normal,
                pressureMetric: 0.1,
                pressureSeries: [],
                capturedAt: date,
                swapUsedBytes: nil
            ),
            rows: [],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 10,
            hostNetworkRates: .missing,
            hostDiskRates: .missing
        )
        _ = core.apply(result: Result<SampledFrame, ProbeError>.success(frame), accepted: true, page: .memory)
    }

    private func sample(at date: Date, cpu: Double?) -> HistorySample {
        HistorySample(
            at: date,
            usedBytes: 100,
            pressure: .normal,
            swapUsedBytes: nil,
            cpuPercent: cpu,
            networkInBytesPerSecond: nil,
            networkOutBytesPerSecond: nil,
            diskReadBytesPerSecond: nil,
            diskWriteBytesPerSecond: nil,
            gpuPercent: nil
        )
    }

    private func repoText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}

private enum ProbeError: Error {
    case unavailable
}
