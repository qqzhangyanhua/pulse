import XCTest
@testable import SamplingCore

/// Memory-page detail attribution. Pure copy only.
/// A pass is not a SwiftUI sidebar, not a snapshot, and not a Mac click.
final class MemoryDetailAttributionTests: XCTestCase {
    func testGroupedHitUsesVisibleMemberCountIncludingOne() {
        let three = copy(magnitude: row(pid: 9, members: 3), curve: row(pid: 9), points: 4, rising: false)
        XCTAssertEqual(three.magnitude, "当前可见的 3 个同名进程合计")

        let one = copy(magnitude: row(pid: 4, members: 1), curve: row(pid: 4), points: 4, rising: false)
        XCTAssertEqual(one.magnitude, "当前可见的 1 个同名进程合计")
    }

    func testMissAndUngroupedRowsUseTheMagnitudePid() {
        let missed = copy(magnitude: row(pid: 99), curve: row(pid: 99), points: 4, rising: true)
        XCTAssertEqual(missed.magnitude, "当前进程（PID 99）")
        XCTAssertFalse(missed.magnitude?.contains("合计") ?? true)

        let alone = copy(magnitude: row(pid: 12), curve: row(pid: 12), points: 2, rising: false)
        XCTAssertEqual(alone.magnitude, "当前进程（PID 12）")
        XCTAssertFalse(alone.magnitude?.contains("合计") ?? true)
    }

    func testEachCallUsesThatRowsCount() {
        let first = copy(magnitude: row(pid: 9, members: 3), curve: row(pid: 9), points: 2, rising: false)
        let second = copy(magnitude: row(pid: 9, members: 1), curve: row(pid: 9), points: 2, rising: false)
        XCTAssertEqual(first.magnitude, "当前可见的 3 个同名进程合计")
        XCTAssertEqual(second.magnitude, "当前可见的 1 个同名进程合计")
    }

    func testRepresentativeMissReturnsToThatPid() {
        let missed = copy(magnitude: row(pid: 15), curve: row(pid: 15), points: 5, rising: false)
        XCTAssertEqual(missed.magnitude, "当前进程（PID 15）")
        XCTAssertFalse(missed.magnitude?.contains("合计") ?? true)
    }

    func testCurveTitleFollowsTheCurveRowWhileTheShareStaysOnTheMagnitudeRow() {
        let magnitude = row(pid: 7, source: .resident, partial: true, members: 3, bytes: 150)
        let curve = row(pid: 7, source: .footprint, bytes: 40)
        let attribution = copy(magnitude: magnitude, curve: curve, points: 3, rising: false)
        let field = MemoryDetailPresentation.field(
            page: .memory,
            part: magnitude.memoryBytes,
            total: 100,
            source: magnitude.memorySource,
            residentIsPartial: magnitude.residentMemoryIsPartial
        )
        XCTAssertEqual(field.title, "驻留内存")
        XCTAssertEqual(field.caption, "占物理内存的 150%（部分按驻留内存计算）")
        XCTAssertEqual(attribution.curveTitle, "内存占用")
        XCTAssertEqual(attribution.magnitude, "当前可见的 3 个同名进程合计")

        let summary = MemoryDetailAttribution.curveSummary(
            pidLine: attribution.curvePid,
            recentAndPeak: recentAndPeak(recent: 1_048_576, peak: 2_097_152)
        )
        XCTAssertEqual(summary, "PID 7 · \(recentAndPeak(recent: 1_048_576, peak: 2_097_152))")
        XCTAssertFalse(summary.contains("部分按驻留"))
        XCTAssertFalse(attribution.curveTitle?.contains("部分") ?? true)
    }

    func testResidentCurveTitleOmitsPartial() {
        let curve = row(pid: 8, source: .resident, partial: true)
        let attribution = copy(magnitude: row(pid: 8, members: 2), curve: curve, points: 2, rising: false)
        XCTAssertEqual(attribution.curveTitle, "驻留内存")
        XCTAssertFalse(attribution.curveTitle?.contains("部分") ?? true)
        let summary = MemoryDetailAttribution.curveSummary(
            pidLine: attribution.curvePid,
            recentAndPeak: recentAndPeak(recent: 1_048_576, peak: 1_048_576)
        )
        XCTAssertFalse(summary.contains("部分"))
    }

    func testZeroAndOnePointLeaveThePidOffAndKeepThePlaceholder() {
        XCTAssertEqual(MemoryDetailAttribution.curvePlaceholder, "正在采集内存曲线")
        for points in [0, 1] {
            let attribution = copy(magnitude: row(pid: 3, members: 2), curve: row(pid: 3), points: points, rising: false)
            XCTAssertNil(attribution.curvePid, "points \(points)")
            let summary = MemoryDetailAttribution.curveSummary(pidLine: attribution.curvePid, recentAndPeak: "")
            XCTAssertEqual(summary, "")
            XCTAssertFalse(summary.contains("PID"))
            XCTAssertNil(attribution.trend, "points \(points)")
        }
    }

    /// One real sample still has a latest value and a peak. The memory page must not show them.
    func testOneRealSampleDoesNotKeepTheRecentPeakSummary() {
        let samples = [
            ChartSample(id: 1, date: Date(timeIntervalSince1970: 1_700_000_000), value: 2_097_152)
        ]
        let sentence = MemoryDetailAttribution.recentAndPeak(samples)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(sentence, "最近 2 MB · 峰值 2 MB")
        XCTAssertFalse(sentence.isEmpty)

        let summary = MemoryDetailAttribution.curveSummary(page: .memory, samples: samples, curvePid: 42)
        XCTAssertEqual(summary, "")
        XCTAssertFalse(summary.contains("最近"))
        XCTAssertFalse(summary.contains("峰值"))
        XCTAssertFalse(summary.contains("PID"))
    }

    func testMemorySummaryPointCountAndOtherPagesStayOnTheSampleSentence() {
        let none: [ChartSample] = []
        XCTAssertEqual(MemoryDetailAttribution.recentAndPeak(none), "")
        XCTAssertEqual(MemoryDetailAttribution.curveSummary(page: .memory, samples: none, curvePid: 7), "")

        let one = [ChartSample(id: 1, date: Date(timeIntervalSince1970: 1_700_000_000), value: 1_048_576)]
        XCTAssertEqual(MemoryDetailAttribution.recentAndPeak(one), "最近 1 MB · 峰值 1 MB")
        XCTAssertEqual(MemoryDetailAttribution.curveSummary(page: .memory, samples: one, curvePid: 7), "")

        let two = [
            ChartSample(id: 1, date: Date(timeIntervalSince1970: 1_700_000_000), value: 5_242_880),
            ChartSample(id: 2, date: Date(timeIntervalSince1970: 1_700_000_003), value: 2_097_152)
        ]
        XCTAssertEqual(MemoryDetailAttribution.recentAndPeak(two), "最近 2 MB · 峰值 5 MB")
        XCTAssertEqual(
            MemoryDetailAttribution.curveSummary(page: .memory, samples: two, curvePid: 7),
            "PID 7 · 最近 2 MB · 峰值 5 MB"
        )

        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            XCTAssertEqual(
                MemoryDetailAttribution.curveSummary(page: page, samples: none, curvePid: 7),
                "",
                "\(page) zero"
            )
            XCTAssertEqual(
                MemoryDetailAttribution.curveSummary(page: page, samples: one, curvePid: 7),
                "最近 1 MB · 峰值 1 MB",
                "\(page) one"
            )
            XCTAssertEqual(
                MemoryDetailAttribution.curveSummary(page: page, samples: two, curvePid: 7),
                "最近 2 MB · 峰值 5 MB",
                "\(page) two"
            )
            XCTAssertFalse(
                MemoryDetailAttribution.curveSummary(page: page, samples: two, curvePid: 7).contains("PID"),
                "\(page)"
            )
        }
    }

    func testTwoOrMorePointsUseTheCurvePidNotTheMemberCount() {
        let attribution = copy(magnitude: row(pid: 42, members: 7), curve: row(pid: 42), points: 2, rising: false)
        XCTAssertEqual(attribution.curvePid, "PID 42")
        let summary = MemoryDetailAttribution.curveSummary(
            pidLine: attribution.curvePid,
            recentAndPeak: recentAndPeak(recent: 512, peak: 2048)
        )
        XCTAssertEqual(summary, "PID 42 · \(recentAndPeak(recent: 512, peak: 2048))")
        XCTAssertFalse(summary.contains("7"))
        XCTAssertFalse(summary.contains("合计"))

        let longer = copy(magnitude: row(pid: 42, members: 7), curve: row(pid: 42), points: 90, rising: false)
        XCTAssertEqual(longer.curvePid, "PID 42")
    }

    func testTrendLineOnlyForARisingMemorySlotAndUsesTheCurvePid() {
        let rising = copy(magnitude: row(pid: 21, members: 4), curve: row(pid: 21), points: 80, rising: true)
        XCTAssertEqual(rising.trend, "这条趋势属于 PID 21")
        XCTAssertFalse(rising.trend?.contains("4") ?? true)

        let insufficient = copy(magnitude: row(pid: 21, members: 4), curve: row(pid: 21), points: 2, rising: false)
        XCTAssertNil(insufficient.trend)
        XCTAssertEqual(insufficient.curvePid, "PID 21")

        let quiet = copy(magnitude: row(pid: 21), curve: row(pid: 21), points: 90, rising: false)
        XCTAssertNil(quiet.trend)

        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            let other = MemoryDetailAttribution.make(
                page: page,
                magnitudeRow: row(pid: 21, members: 4),
                curveRow: row(pid: 21),
                memoryPointCount: 90,
                trendIsRising: true
            )
            XCTAssertNil(other.magnitude, "\(page)")
            XCTAssertNil(other.curveTitle, "\(page)")
            XCTAssertNil(other.curvePid, "\(page)")
            XCTAssertNil(other.trend, "\(page)")
            let sentence = recentAndPeak(recent: 1_048_576, peak: 1_048_576)
            let summary = MemoryDetailAttribution.curveSummary(
                pidLine: other.curvePid,
                recentAndPeak: sentence
            )
            XCTAssertEqual(summary, sentence, "\(page)")
            XCTAssertFalse(summary.contains("PID"), "\(page)")
            XCTAssertFalse(summary.contains("这条趋势属于"), "\(page)")
        }
    }

    func testSentencesOmitAppWideClaims() {
        let attribution = copy(magnitude: row(pid: 1, members: 3), curve: row(pid: 1), points: 4, rising: true)
        let summary = MemoryDetailAttribution.curveSummary(
            pidLine: attribution.curvePid,
            recentAndPeak: recentAndPeak(recent: 1, peak: 2)
        )
        let blob = [attribution.magnitude, attribution.curveTitle, summary, attribution.trend]
            .compactMap { $0 }
            .joined(separator: "\n")
        for banned in ["整个 App", "全部成员", "完整 App", "App 趋势", "App 的内存"] {
            XCTAssertFalse(blob.contains(banned), banned)
        }
    }

    func testModelDoesNotEvaluateOrReadTheSampler() throws {
        let source = try repoText("Pulse/Models/MemoryDetailAttribution.swift")
        XCTAssertFalse(source.contains("MemoryGrowthSignal"))
        XCTAssertFalse(source.contains(".evaluate"))
        XCTAssertFalse(source.contains("MemorySampler"))
        XCTAssertFalse(source.contains("groupedByApp"))
        XCTAssertFalse(source.contains("import SwiftUI"))
        XCTAssertFalse(source.contains("import Darwin"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertTrue(source.contains("当前可见的"))
        XCTAssertTrue(source.contains("当前进程（PID"))
        XCTAssertTrue(source.contains("这条趋势属于 PID"))
        XCTAssertEqual(
            occurrenceCount(of: "static let curvePlaceholder = \"正在采集内存曲线\"", in: source),
            1
        )
    }

    private func copy(
        magnitude: ProcessRow,
        curve: ProcessRow,
        points: Int,
        rising: Bool
    ) -> MemoryDetailAttribution {
        MemoryDetailAttribution.make(
            page: .memory,
            magnitudeRow: magnitude,
            curveRow: curve,
            memoryPointCount: points,
            trendIsRising: rising
        )
    }

    private func row(
        pid: Int32,
        source: ProcessMemorySource = .footprint,
        partial: Bool = false,
        members: Int? = nil,
        bytes: UInt64 = 1_048_576
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: "Example",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: bytes,
            memorySource: source,
            residentMemoryIsPartial: partial,
            threadCount: 1,
            groupedMemberCount: members
        )
    }

    private func recentAndPeak(recent: UInt64, peak: UInt64) -> String {
        "最近 \(ByteFormat.memory(recent)) · 峰值 \(ByteFormat.memory(peak))"
    }

    private func repoText(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
