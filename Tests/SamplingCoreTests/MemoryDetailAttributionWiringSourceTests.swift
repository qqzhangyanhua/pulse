import XCTest
@testable import SamplingCore

/// Sidebar source contract for memory-detail attribution.
/// Linux reads source text. A pass is not a sidebar click and not VoiceOver.
final class MemoryDetailAttributionWiringSourceTests: XCTestCase {
    func testModelIsPortableAndRegistered() throws {
        let source = try repoText("Pulse/Models/MemoryDetailAttribution.swift")
        XCTAssertTrue(source.contains("struct MemoryDetailAttribution"))
        XCTAssertFalse(source.contains("import SwiftUI"))
        XCTAssertFalse(source.contains("import Darwin"))
        XCTAssertFalse(source.contains("import AppKit"))
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/MemoryDetailAttribution.swift\""))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("MemoryDetailAttribution.swift in Sources"))
        XCTAssertTrue(project.contains("path = MemoryDetailAttribution.swift;"))
    }

    func testMemoryPageWritesAttributionAndCpuDetailDoesNot() throws {
        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        let detail = try functionBody(named: "detailBody", in: sidebar)
        XCTAssertLessThan(
            try index(of: "memoryTrend(slot, curveRow: detail.row)", in: detail),
            try index(of: "memoryChart(detail)", in: detail)
        )

        let metrics = try functionBody(named: "metrics", in: sidebar)
        XCTAssertEqual(occurrenceCount(of: "attribution:", in: metrics), 1)
        XCTAssertTrue(metrics.contains("memoryMagnitudeAttribution("))
        XCTAssertTrue(metrics.contains("displayedMemoryRow(detail.row)"))
        XCTAssertTrue(metrics.contains("curve: detail.row"))
        XCTAssertFalse(metrics.contains("当前可见的"))
        XCTAssertFalse(metrics.contains("caption: memory.caption +"))

        let chart = try functionBody(named: "memoryChart", in: sidebar)
        XCTAssertTrue(chart.contains("vm.selectedPage == .memory"))
        XCTAssertTrue(chart.contains("curveRow: detail.row"))
        XCTAssertTrue(chart.contains("memoryField(displayedMemoryRow(detail.row))"))
        XCTAssertTrue(chart.contains("MemoryDetailAttribution.curveSummary"))
        XCTAssertTrue(chart.contains("memorySummary(detail.memorySeries)"))
        XCTAssertTrue(chart.contains("正在采集内存曲线"))
        XCTAssertFalse(chart.contains("memoryField(detail.row)"))
        XCTAssertFalse(chart.contains("title: \"内存\""))

        let trend = try functionBody(named: "memoryTrend", in: sidebar)
        XCTAssertTrue(trend.contains("curveRow: curveRow"))
        XCTAssertTrue(trend.contains("trendIsRising: slot.caption == MemoryGrowthCopy.rising"))
        XCTAssertLessThan(try index(of: "Text(trend)", in: trend), try index(of: "accessibilityElement(children: .combine)", in: trend))
        XCTAssertTrue(trend.contains("slot.title"))
        XCTAssertTrue(trend.contains("slot.caption"))
        XCTAssertTrue(trend.contains("slot.basis"))
        XCTAssertFalse(trend.contains("accessibilityLabel"))
        XCTAssertEqual(occurrenceCount(of: "accessibilityElement(children: .combine)", in: trend), 1)

        let cpuDetail = try functionBody(named: "cpuResourceDetail", in: sidebar)
        XCTAssertFalse(cpuDetail.contains("MemoryDetailAttribution"))
        XCTAssertFalse(cpuDetail.contains("attribution:"))
        XCTAssertFalse(cpuDetail.contains("当前可见的"))
        XCTAssertFalse(cpuDetail.contains("当前进程（PID"))
        XCTAssertFalse(cpuDetail.contains("这条趋势属于"))

        let cpuChart = try functionBody(named: "cpuChart", in: sidebar)
        XCTAssertFalse(cpuChart.contains("MemoryDetailAttribution"))
        XCTAssertFalse(cpuChart.contains("PID"))
        XCTAssertTrue(cpuChart.contains("title: \"CPU\""))
        XCTAssertTrue(cpuChart.contains("正在采集 CPU 曲线"))

        let memoryMetric = try functionBody(named: "memoryMetric", in: sidebar)
        XCTAssertFalse(memoryMetric.contains("attribution:"))
        XCTAssertFalse(memoryMetric.contains("MemoryDetailAttribution"))

        let absent = try functionBody(named: "absentRecordBody", in: sidebar)
        XCTAssertFalse(absent.contains("MemoryDetailAttribution"))
        let empty = try functionBody(named: "emptyBody", in: sidebar)
        XCTAssertFalse(empty.contains("MemoryDetailAttribution"))

        let magnitude = try functionBody(named: "memoryMagnitudeAttribution", in: sidebar)
        XCTAssertTrue(magnitude.contains("guard vm.selectedPage == .memory else { return nil }"))
        XCTAssertTrue(magnitude.contains("magnitudeRow: displayed"))
        XCTAssertTrue(magnitude.contains("curveRow: curve"))
        XCTAssertFalse(magnitude.contains("groupedByApp"))
        XCTAssertFalse(magnitude.contains(".evaluate"))
    }

    func testAttributionIsVisibleTextWithAnEmptyDefault() throws {
        let metric = try repoText("Pulse/Views/SharedUI.swift")
        let body = try functionBody(named: "body", in: metric, typeName: "struct SidebarMetric")
        XCTAssertTrue(metric.contains("var attribution: String? = nil"))
        XCTAssertTrue(body.contains("Text(attribution)"))
        XCTAssertFalse(body.contains(".help(attribution"))
        XCTAssertFalse(body.contains("accessibilityLabel"))
        XCTAssertTrue(body.contains("captionText"))
        XCTAssertLessThan(try index(of: "captionText", in: body), try index(of: "Text(attribution)", in: body))
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

    private func functionBody(named name: String, in source: String, typeName: String? = nil) throws -> String {
        let patterns = ["func \(name)(", "func \(name)()", "private func \(name)(", "var \(name):"]
        var search = source[...]
        if let typeName, let typeRange = source.range(of: typeName) {
            search = source[typeRange.lowerBound...]
        }
        for pattern in patterns {
            guard let range = search.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw AttributionSourceError.missing(name)
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw AttributionSourceError.missing(needle)
        }
        return found
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        var depth = 0
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...cursor]) }
            }
            cursor = source.index(after: cursor)
        }
        throw AttributionSourceError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum AttributionSourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
