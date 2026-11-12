import XCTest
@testable import SamplingCore

/// Phase 21 source wiring. Linux SamplingCore does not compile Views or the VM.
/// These tests read source text. They do not draw SwiftUI, run VoiceOver, or
/// prove a Mac overlay. Direction is the per-side call and `"\(title) · \(note)"`,
/// not a count of the bare sentence.
final class HistoryCurveWiringSourceTests: XCTestCase {
    private let sentence = "历史曲线 · 当前值暂不可用"
    private let cpuAnnotation = "annotation(current: vm.systemCpuPercent, sampleCount: vm.cpuHistory.samples.count)"
    private let rateAnnotation = "annotation(current: rate, sampleCount: samples.count)"

    func testPackageListsTheModelAndKeepsViewsOut() throws {
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/HistoryCurvePresentation.swift\""))
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))
        XCTAssertFalse(package.contains("HistoryAnnotatedChart"))
        XCTAssertFalse(package.contains("SharedUI.swift"))
        XCTAssertFalse(package.contains("CPUOverviewSection.swift"))
        XCTAssertFalse(package.contains("NetworkOverviewSection.swift"))
        XCTAssertFalse(package.contains("DiskOverviewSection.swift"))
    }

    func testProjectRegistersTheModelInFourPlaces() throws {
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        let build = try markedSection("PBXBuildFile", in: project)
        let refs = try markedSection("PBXFileReference", in: project)
        let models = try modelsGroup(in: project)
        let sources = try markedSection("PBXSourcesBuildPhase", in: project)
        XCTAssertTrue(build.contains("HistoryCurvePresentation.swift in Sources"))
        XCTAssertTrue(refs.contains("path = HistoryCurvePresentation.swift;"))
        XCTAssertTrue(models.contains("HistoryCurvePresentation.swift"))
        XCTAssertTrue(sources.contains("HistoryCurvePresentation.swift in Sources"))
        XCTAssertFalse(project.contains("HistoryAnnotatedChart.swift"))
    }

    func testModelSurfaceIsOnlyUnavailableAndAnnotation() throws {
        let model = try repoText("Pulse/Models/HistoryCurvePresentation.swift")
        XCTAssertFalse(model.contains("import"))
        XCTAssertFalse(model.contains("SwiftUI"))
        XCTAssertFalse(model.contains("Date"))
        XCTAssertFalse(model.contains("title"))
        XCTAssertFalse(model.contains("unavailableCaption"))
        XCTAssertEqual(occurrenceCount(of: "static func", in: model), 1)
        XCTAssertTrue(model.contains("static let unavailable = \"\(sentence)\""))
        XCTAssertTrue(model.contains("static func annotation(current: Double?, sampleCount: Int) -> String?"))
        XCTAssertTrue(compact(model).contains("guardcurrent==nil,sampleCount>=2else{returnnil}returnunavailable"))
    }

    func testWrapperAndSparklineBodiesStaySeparate() throws {
        let shared = try repoText("Pulse/Views/SharedUI.swift")
        let wrapper = try typeBody(named: "HistoryAnnotatedChart", keyword: "struct", in: shared)
        let spark = try typeBody(named: "SparklineChart", keyword: "struct", in: shared)
        for needle in [
            "overlay(alignment: .topLeading)",
            ".font(.caption2)",
            ".foregroundStyle(.secondary)",
            ".lineLimit(1)",
            ".truncationMode(.tail)",
            ".padding(.top, 5)",
            ".padding(.leading, 5)",
        ] {
            XCTAssertTrue(wrapper.contains(needle), needle)
        }
        for forbidden in [
            "chartXAxis",
            "chartYAxis",
            "accessibilityLabel",
            "allowsHitTesting",
            "animation",
            "transition",
            ".opacity",
        ] {
            XCTAssertFalse(wrapper.contains(forbidden), forbidden)
        }
        XCTAssertTrue(spark.contains("tint.opacity(0.42)"))
        XCTAssertTrue(spark.contains("tint.opacity(0.02)"))
        XCTAssertTrue(spark.contains("Color.white.opacity(0.42)"))
        XCTAssertTrue(spark.contains("Color.white.opacity(0.06)"))
        XCTAssertTrue(spark.contains("chartXAxis"))
        XCTAssertTrue(spark.contains("chartYAxis"))
        XCTAssertFalse(spark.contains("annotation"))
        XCTAssertFalse(spark.contains("HistoryCurvePresentation"))
        XCTAssertEqual(occurrenceCount(of: "struct SparklineChart", in: shared), 1)
        XCTAssertEqual(occurrenceCount(of: "struct HistoryAnnotatedChart", in: shared), 1)
    }

    func testCPUReadyElseUsesItsOwnCurrentAndSamples() throws {
        let cpu = try repoText("Pulse/Views/CPUOverviewSection.swift")
        XCTAssertEqual(occurrenceCount(of: "HistoryAnnotatedChart", in: cpu), 1)
        XCTAssertEqual(occurrenceCount(of: cpuAnnotation, in: cpu), 2)
        XCTAssertFalse(cpu.contains(sentence))
        XCTAssertFalse(cpu.contains("directedHistoryNote"))

        let chart = try functionBody(named: "chart", in: cpu)
        let branches = try chartBranches(chart)
        XCTAssertTrue(chart.contains("vm.cpuHistory.samples.count < 2"))
        XCTAssertTrue(branches.placeholder.contains("ChartPlaceholder(text: \"曲线采集中\")"))
        XCTAssertFalse(branches.placeholder.contains("HistoryAnnotatedChart"))
        XCTAssertFalse(branches.placeholder.contains("HistoryCurvePresentation"))
        XCTAssertEqual(occurrenceCount(of: "HistoryAnnotatedChart", in: branches.sparkline), 1)
        XCTAssertEqual(occurrenceCount(of: cpuAnnotation, in: branches.sparkline), 1)
        XCTAssertTrue(branches.sparkline.contains("samples: vm.cpuHistory.samples"))
        XCTAssertTrue(branches.sparkline.contains("domain: domain"))
        XCTAssertTrue(branches.sparkline.contains("CPUPercentText.string($0)"))

        let ready = try functionBody(named: "readyBody", in: cpu)
        XCTAssertTrue(ready.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(ready.contains(".accessibilityLabel(readyAccessibilityLabel)"))
        XCTAssertFalse(ready.contains("HistoryAnnotatedChart"))
        XCTAssertFalse(ready.contains(sentence))

        let label = try functionBody(named: "readyAccessibilityLabel", in: cpu)
        let labelCode = compact(label)
        XCTAssertEqual(occurrenceCount(of: cpuAnnotation, in: label), 1)
        XCTAssertTrue(labelCode.contains("return\"\\(overviewLine)，\\(note)\""))
        XCTAssertTrue(labelCode.contains("returnoverviewLine"))
        XCTAssertFalse(label.contains("inboundTitle"))
        XCTAssertFalse(label.contains("outboundTitle"))
        XCTAssertFalse(label.contains("readTitle"))
        XCTAssertFalse(label.contains("writeTitle"))
        XCTAssertFalse(label.contains(sentence))

        let sampling = try functionBody(named: "samplingBody", in: cpu)
        let failure = try functionBody(named: "failureBody", in: cpu)
        XCTAssertFalse(sampling.contains("HistoryAnnotatedChart"))
        XCTAssertFalse(sampling.contains("HistoryCurvePresentation"))
        XCTAssertFalse(failure.contains("HistoryAnnotatedChart"))
        XCTAssertFalse(failure.contains("HistoryCurvePresentation"))
        XCTAssertTrue(sampling.contains(".accessibilityElement(children: .combine)"))
    }

    func testNetworkDirectionsKeepSeparateCurrentSampleAndTitleNotes() throws {
        try assertDirectionCard(
            file: "Pulse/Views/NetworkOverviewSection.swift",
            card: "NetworkRateCard",
            placeholder: "ChartPlaceholder(text: NetworkPageCopy.chartCollecting)",
            firstRate: "vm.hostNetworkRates.inboundBytesPerSecond",
            firstSamples: "vm.networkHistory.inbound.samples",
            secondRate: "vm.hostNetworkRates.outboundBytesPerSecond",
            secondSamples: "vm.networkHistory.outbound.samples",
            firstTitle: "NetworkPageCopy.inboundTitle",
            secondTitle: "NetworkPageCopy.outboundTitle",
            forbiddenRateFields: ["hostNetworkRates", "networkHistory"]
        )
    }

    func testDiskDirectionsKeepSeparateCurrentSampleAndTitleNotes() throws {
        try assertDirectionCard(
            file: "Pulse/Views/DiskOverviewSection.swift",
            card: "DiskRateCard",
            placeholder: "ChartPlaceholder(text: DiskPageCopy.chartCollecting)",
            firstRate: "vm.hostDiskRates.readBytesPerSecond",
            firstSamples: "vm.diskHistory.read.samples",
            secondRate: "vm.hostDiskRates.writeBytesPerSecond",
            secondSamples: "vm.diskHistory.write.samples",
            firstTitle: "DiskPageCopy.readTitle",
            secondTitle: "DiskPageCopy.writeTitle",
            forbiddenRateFields: ["hostDiskRates", "diskHistory"]
        )
    }

    func testOutOfScopeSurfacesAndPhase20CountsStay() throws {
        for relative in [
            "Pulse/Views/OverviewCards.swift",
            "Pulse/Views/ProcessDetailSidebar.swift",
            "Pulse/Views/OverviewSection.swift",
            "Pulse/Views/ProcessTablePane.swift",
            "Pulse/ViewModels/MemoryDashboardVM.swift",
            "Pulse/Models/TopAppLocation.swift",
            "Pulse/Models/ResourceDetailPageProjection.swift",
        ] {
            let text = try forbiddenSurfaceText(relative)
            XCTAssertFalse(text.contains("HistoryCurvePresentation"), relative)
            XCTAssertFalse(text.contains("HistoryAnnotatedChart"), relative)
            XCTAssertFalse(text.contains(sentence), relative)
        }

        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        let series = try functionBody(named: "seriesBlock", in: sidebar)
        XCTAssertTrue(series.contains("SparklineChart(samples: samples, tint: tint, domain: domain, formatY: formatY)"))

        let cards = try repoText("Pulse/Views/OverviewCards.swift")
        XCTAssertGreaterThanOrEqual(occurrenceCount(of: "SparklineChart(", in: cards), 2)
        XCTAssertFalse(cards.contains("annotation:"))

        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        XCTAssertEqual(occurrenceCount(of: "@Published", in: vm), 32, "battery card adds energyBatteryCard; energy page adds energyWindowRates; permission footnote adds processPermissionFootnote; energy history adds energyMachineHistory")
        XCTAssertEqual(occurrenceCount(of: "didSet", in: vm), 4)
        XCTAssertEqual(occurrenceCount(of: "@MainActor", in: vm), 1)
        let sortedLine = try lineContaining("var sortedRows", in: vm)
        XCTAssertFalse(sortedLine.contains("@Published"))
        let sorted = try functionBody(named: "sortedRows", in: vm)
        XCTAssertTrue(compact(sorted).contains("AppGroupProjection.apply(rows:visibleRows"))
        let locate = try functionBody(named: "locateMemoryTopApp", in: vm)
        XCTAssertTrue(locate.contains("guard let plan"))
        XCTAssertTrue(locate.contains("filter ="))
        XCTAssertTrue(locate.contains("risingOnlyFilter = false"))
        XCTAssertTrue(locate.contains("selectPidIfPresent"))
        XCTAssertTrue(locate.contains("topAppLocateReveal"))

        let pane = try repoText("Pulse/Views/ProcessTablePane.swift")
        let phase = try functionBody(named: "cpuPhase", in: pane)
        XCTAssertTrue(phase.contains("CPUPagePhaseResolver.resolve"))
        let table = try functionBody(named: "resourceTableBody", in: pane)
        XCTAssertTrue(table.contains("switch cpuPhase"))
        XCTAssertTrue(pane.contains("row.networkAvailability.label"))

        let views = repoRoot().appendingPathComponent("Pulse/Views", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let charts = occurrenceCount(of: "HistoryAnnotatedChart", in: text)
            switch file.lastPathComponent {
            case "CPUOverviewSection.swift", "NetworkOverviewSection.swift", "DiskOverviewSection.swift":
                XCTAssertEqual(charts, 1, file.lastPathComponent)
            case "MachineOverviewSection.swift":
                XCTAssertEqual(charts, 1, "CPU and memory share one annotated chart")
            case "SharedUI.swift":
                XCTAssertEqual(charts, 1, "wrapper type lives in SharedUI")
            default:
                XCTAssertEqual(charts, 0, file.lastPathComponent)
            }
        }
    }

    private func assertDirectionCard(
        file: String,
        card cardName: String,
        placeholder: String,
        firstRate: String,
        firstSamples: String,
        secondRate: String,
        secondSamples: String,
        firstTitle: String,
        secondTitle: String,
        forbiddenRateFields: [String]
    ) throws {
        let source = try repoText(file)
        XCTAssertEqual(occurrenceCount(of: "HistoryAnnotatedChart", in: source), 1, file)
        XCTAssertFalse(source.contains(sentence), file)
        XCTAssertEqual(occurrenceCount(of: "\"\\(title) · \\(note)\"", in: source), 1, file)

        let ready = try functionBody(named: "readyBody", in: source)
        let readyCode = compact(ready)
        let firstPair = "rate:\(firstRate),samples:\(firstSamples)"
        let secondPair = "rate:\(secondRate),samples:\(secondSamples)"
        XCTAssertEqual(occurrenceCount(of: firstPair, in: readyCode), 1, file)
        XCTAssertEqual(occurrenceCount(of: secondPair, in: readyCode), 1, file)
        let firstAt = try index(of: firstPair, in: readyCode)
        let secondAt = try index(of: secondPair, in: readyCode)
        XCTAssertLessThan(firstAt, secondAt, file)
        XCTAssertFalse(ready.contains("HistoryAnnotatedChart"), file)
        XCTAssertTrue(ready.contains(".accessibilityElement(children: .ignore)"), file)
        XCTAssertTrue(ready.contains(".accessibilityLabel(readyAccessibilityLabel)"), file)
        XCTAssertFalse(ready.contains("HistoryCurvePresentation"), file)

        let card = try typeBody(named: cardName, keyword: "struct", in: source)
        for field in forbiddenRateFields {
            XCTAssertFalse(card.contains(field), "\(file) \(field)")
        }
        XCTAssertEqual(occurrenceCount(of: "HistoryAnnotatedChart", in: card), 1, file)
        let chart = try functionBody(named: "chart", in: card)
        XCTAssertTrue(chart.contains("samples.count < 2"))
        let branches = try chartBranches(chart)
        XCTAssertTrue(branches.placeholder.contains(placeholder), file)
        XCTAssertFalse(branches.placeholder.contains("HistoryAnnotatedChart"), file)
        XCTAssertFalse(branches.placeholder.contains("HistoryCurvePresentation"), file)
        XCTAssertEqual(occurrenceCount(of: "HistoryAnnotatedChart", in: branches.sparkline), 1, file)
        XCTAssertEqual(occurrenceCount(of: rateAnnotation, in: branches.sparkline), 1, file)
        XCTAssertTrue(branches.sparkline.contains("samples: samples"), file)
        XCTAssertTrue(branches.sparkline.contains("domain: domain"), file)
        XCTAssertFalse(branches.sparkline.contains("inboundTitle"), file)
        XCTAssertFalse(branches.sparkline.contains("outboundTitle"), file)
        XCTAssertFalse(branches.sparkline.contains("readTitle"), file)
        XCTAssertFalse(branches.sparkline.contains("writeTitle"), file)
        XCTAssertFalse(branches.sparkline.contains(sentence), file)

        let label = try functionBody(named: "readyAccessibilityLabel", in: source)
        let labelCode = compact(label)
        let firstCall = "annotation(current:\(firstRate),sampleCount:\(firstSamples).count)"
        let secondCall = "annotation(current:\(secondRate),sampleCount:\(secondSamples).count)"
        XCTAssertEqual(occurrenceCount(of: firstCall, in: labelCode), 1, file)
        XCTAssertEqual(occurrenceCount(of: secondCall, in: labelCode), 1, file)
        let firstTitleAt = try index(of: firstTitle, in: labelCode)
        let firstCallAt = try index(of: firstCall, in: labelCode)
        let secondTitleAt = try index(of: secondTitle, in: labelCode)
        let secondCallAt = try index(of: secondCall, in: labelCode)
        XCTAssertLessThan(firstTitleAt, firstCallAt, file)
        XCTAssertLessThan(firstCallAt, secondTitleAt, file)
        XCTAssertLessThan(secondTitleAt, secondCallAt, file)
        XCTAssertFalse(label.contains("||"), file)
        XCTAssertFalse(label.contains(sentence), file)
        XCTAssertTrue(labelCode.contains("guard!notes.isEmptyelse{returnoverviewLine}"), file)
        XCTAssertTrue(labelCode.contains("return([overviewLine]+notes).joined(separator:\"，\")"), file)

        let helper = try functionBody(named: "directedHistoryNote", in: source)
        let helperCode = compact(helper)
        XCTAssertTrue(helperCode.contains("guardletnoteelse{returnnil}"), file)
        XCTAssertTrue(helperCode.contains("return\"\\(title)·\\(note)\""), file)
        XCTAssertFalse(helper.contains("annotation"), file)
        XCTAssertFalse(helper.contains("HistoryCurvePresentation"), file)
        XCTAssertFalse(helper.contains(sentence), file)
        XCTAssertEqual(occurrenceCount(of: "func directedHistoryNote(", in: source), 1, file)

        let sampling = try functionBody(named: "samplingBody", in: source)
        let failure = try functionBody(named: "failureBody", in: source)
        XCTAssertFalse(sampling.contains("HistoryAnnotatedChart"), file)
        XCTAssertFalse(sampling.contains("HistoryCurvePresentation"), file)
        XCTAssertFalse(failure.contains("HistoryAnnotatedChart"), file)
        XCTAssertFalse(failure.contains("HistoryCurvePresentation"), file)
        XCTAssertTrue(sampling.contains(".accessibilityElement(children: .combine)"), file)
    }

    private func forbiddenSurfaceText(_ relative: String) throws -> String {
        switch relative {
        case "Pulse/Views/ProcessDetailSidebar.swift":
            return try WiringSourceText.text(for: "ProcessDetailSidebar")
        case "Pulse/ViewModels/MemoryDashboardVM.swift":
            return try WiringSourceText.text(for: "MemoryDashboardVM")
        default:
            return try repoText(relative)
        }
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

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = [
            "var \(name):",
            "func \(name)(",
            "func \(name)()",
            "private func \(name)(",
            "private func \(name)()",
        ]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw SourceSliceError.missing("declaration for \(name)")
    }

    private func typeBody(named name: String, keyword: String, in source: String) throws -> String {
        guard let start = source.range(of: "\(keyword) \(name)")?.lowerBound else {
            throw SourceSliceError.missing("\(keyword) \(name)")
        }
        guard let brace = source[start...].firstIndex(of: "{") else {
            throw SourceSliceError.missing("body for \(name)")
        }
        return try balancedSlice(from: brace, in: source, label: name)
    }

    private func chartBranches(_ chartBody: String) throws -> (placeholder: String, sparkline: String) {
        guard let ifToken = chartBody.range(of: "if ") else {
            throw SourceSliceError.missing("chart if")
        }
        guard let ifBrace = chartBody[ifToken.upperBound...].firstIndex(of: "{") else {
            throw SourceSliceError.missing("chart if body")
        }
        let placeholder = try balancedSlice(from: ifBrace, in: chartBody, label: "chart if")
        guard let placeholderRange = chartBody.range(of: placeholder, range: ifBrace..<chartBody.endIndex) else {
            throw SourceSliceError.missing("chart if range")
        }
        guard let elseToken = chartBody[placeholderRange.upperBound...].range(of: "else") else {
            throw SourceSliceError.missing("chart else")
        }
        guard let elseBrace = chartBody[elseToken.upperBound...].firstIndex(of: "{") else {
            throw SourceSliceError.missing("chart else body")
        }
        let sparkline = try balancedSlice(from: elseBrace, in: chartBody, label: "chart else")
        return (placeholder, sparkline)
    }

    private func markedSection(_ name: String, in source: String) throws -> String {
        let begin = "/* Begin \(name) section */"
        let end = "/* End \(name) section */"
        guard let start = source.range(of: begin)?.upperBound,
              let stop = source.range(of: end)?.lowerBound,
              start < stop
        else {
            throw SourceSliceError.missing(name)
        }
        return String(source[start..<stop])
    }

    private func modelsGroup(in source: String) throws -> String {
        guard let start = source.range(of: "/* Models */")?.lowerBound else {
            throw SourceSliceError.missing("Models group")
        }
        guard let stop = source.range(of: "path = Models;", range: start..<source.endIndex)?.upperBound else {
            throw SourceSliceError.missing("Models path")
        }
        return String(source[start..<stop])
    }

    private func lineContaining(_ needle: String, in source: String) throws -> String {
        guard let line = source.components(separatedBy: .newlines).first(where: { $0.contains(needle) }) else {
            throw SourceSliceError.missing(needle)
        }
        return line
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw SourceSliceError.missing(needle)
        }
        return found
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        let opener = source[start]
        let closer: Character = opener == "(" ? ")" : "}"
        var depth = 0
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == opener { depth += 1 }
            if character == closer {
                depth -= 1
                if depth == 0 {
                    return String(source[start...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }
        throw SourceSliceError.missing("balanced \(opener) for \(label)")
    }

    private func compact(_ source: String) -> String {
        let withoutLineComments = source.components(separatedBy: .newlines).map { line -> String in
            guard let marker = line.range(of: "//") else { return line }
            return String(line[..<marker.lowerBound])
        }.joined(separator: "\n")
        return withoutLineComments.filter { !$0.isWhitespace }
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum SourceSliceError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case .missing(let detail):
            return "missing \(detail)"
        }
    }
}
