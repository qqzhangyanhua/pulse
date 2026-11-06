import XCTest
@testable import SamplingCore

/// Phase 22 source wiring. Linux SamplingCore does not compile Views or the VM.
/// These tests read source text. They do not draw SwiftUI, run tooltip, or VoiceOver.
final class MemoryGrowthListHelpWiringSourceTests: XCTestCase {
    private let lockedHelp =
        "完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期驻留内存序列判断趋势。"
    private let toggleNeedle =
        "Toggle(MemoryRisingOnlyChrome.toggleTitle, isOn: $vm.risingOnlyFilter)"
    private let helpModifier = ".help(MemoryGrowthListCopy.help)"

    func testToggleHelpReadsTheSharedListCopyIdentifier() throws {
        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        XCTAssertEqual(occurrenceCount(of: helpModifier, in: dashboard), 1)
        XCTAssertTrue(dashboard.contains(toggleNeedle))
        XCTAssertTrue(dashboard.contains(".toggleStyle(.switch)"))
        XCTAssertTrue(dashboard.contains(".controlSize(.small)"))
        XCTAssertTrue(dashboard.contains("showsToggle(page: vm.selectedPage)"))
        XCTAssertFalse(dashboard.contains(lockedHelp))
        XCTAssertFalse(dashboard.contains("risingOnlyFilter = false"))

        let chain = try toggleHelpChain(in: dashboard)
        XCTAssertTrue(chain.contains(".toggleStyle(.switch)"))
        XCTAssertTrue(chain.contains(".controlSize(.small)"))
        XCTAssertTrue(chain.contains(helpModifier))
        XCTAssertFalse(chain.contains(".disabled"))

        let toggle = try range(of: toggleNeedle, in: dashboard)
        let field = try range(of: "AppFilterField(text: $vm.filter)", in: dashboard)
        XCTAssertLessThan(toggle.lowerBound, field.lowerBound)
    }

    func testLockedHelpLiteralLivesOnlyOnStaticLetHelp() throws {
        let signal = try repoText("Pulse/Models/MemoryGrowthSignal.swift")
        XCTAssertEqual(occurrenceCount(of: lockedHelp, in: signal), 1)
        let copy = try typeBody(named: "MemoryGrowthListCopy", keyword: "enum", in: signal)
        let helpLine = try lineContaining("static let help", in: copy)
        XCTAssertEqual(
            helpLine.trimmingCharacters(in: .whitespaces),
            "static let help = \"\(lockedHelp)\""
        )
        let titleLine = try lineContaining("static let title", in: copy)
        XCTAssertEqual(titleLine.trimmingCharacters(in: .whitespaces), "static let title = \"上涨\"")

        let badge = try functionBody(named: "badge", in: signal)
        XCTAssertTrue(badge.contains("help: MemoryGrowthListCopy.help"))
        XCTAssertTrue(badge.contains("title: MemoryGrowthListCopy.title"))
        XCTAssertFalse(badge.contains(lockedHelp))
        XCTAssertFalse(badge.contains(".help("))

        let badgeType = try typeBody(named: "MemoryGrowthListBadge", keyword: "struct", in: signal)
        XCTAssertTrue(badgeType.contains("let title: String"))
        XCTAssertTrue(badgeType.contains("let help: String"))
        XCTAssertEqual(occurrenceCount(of: "let ", in: badgeType), 2)
    }

    func testBadgeAndParentRowStillReadTheInstanceHelpField() throws {
        let pane = try repoText("Pulse/Views/ProcessTablePane.swift")
        let chip = try typeBody(named: "MemoryGrowthRisingBadge", keyword: "struct", in: pane)
        XCTAssertTrue(chip.contains(".help(badge.help)"))
        XCTAssertTrue(chip.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(chip.contains(helpModifier))
        XCTAssertFalse(chip.contains(lockedHelp))
        XCTAssertFalse(chip.contains(".help(\""))

        let label = try functionBody(named: "accessibilityLabel", in: pane)
        XCTAssertTrue(label.contains("parts.append(growthBadge.help)"))
        XCTAssertFalse(label.contains(helpModifier))
        XCTAssertFalse(label.contains(lockedHelp))

        let row = try typeBody(named: "ProcessLine", keyword: "struct", in: pane)
        XCTAssertTrue(row.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertFalse(pane.contains(lockedHelp))
        XCTAssertFalse(pane.contains("MemoryGrowthListCopy.help"))
    }

    func testViewModelHasNoHelpModelSource() throws {
        let source = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertFalse(source.contains(lockedHelp))
        XCTAssertFalse(source.contains("MemoryGrowthListCopy"))
        XCTAssertEqual(occurrenceCount(of: "@Published", in: source), 23)
        XCTAssertEqual(occurrenceCount(of: "didSet", in: source), 2)
        XCTAssertEqual(occurrenceCount(of: "@MainActor", in: source), 1)

        let badge = try functionBody(named: "memoryGrowthListBadge", in: source)
        XCTAssertTrue(compact(badge).contains("MemoryGrowthList.badge("))
        XCTAssertTrue(compact(badge).contains("seriesByPid:topMemorySeries"))

        let sorted = try functionBody(named: "sortedRows", in: source)
        XCTAssertTrue(compact(sorted).contains("tableSort.ordered(visibleRows)"))
        XCTAssertFalse(compact(sorted).contains("ordered(rows)"))
    }

    func testPackageAndProjectKeepTheExistingSignalRegistration() throws {
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/MemoryGrowthSignal.swift\""))
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))
        XCTAssertTrue(package.contains("\"Sampling/MemorySampler.swift\""))
        XCTAssertFalse(package.contains("MemoryDashboardVM.swift"))
        XCTAssertFalse(package.contains("ProcessTablePane.swift"))
        XCTAssertFalse(package.contains("MemoryDashboardView.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        let build = try markedSection("PBXBuildFile", in: project)
        let refs = try markedSection("PBXFileReference", in: project)
        let models = try modelsGroup(in: project)
        let sources = try markedSection("PBXSourcesBuildPhase", in: project)
        XCTAssertEqual(occurrenceCount(of: "isa = PBXBuildFile", in: build), 51)
        XCTAssertEqual(occurrenceCount(of: "MemoryGrowthSignal.swift in Sources", in: build), 1)
        XCTAssertTrue(refs.contains("path = MemoryGrowthSignal.swift;"))
        XCTAssertTrue(models.contains("MemoryGrowthSignal.swift"))
        XCTAssertTrue(sources.contains("MemoryGrowthSignal.swift in Sources"))
    }

    private func toggleHelpChain(in dashboard: String) throws -> String {
        let toggle = try range(of: toggleNeedle, in: dashboard)
        let help = try range(of: helpModifier, in: dashboard)
        guard toggle.lowerBound < help.upperBound else {
            throw SourceSliceError.missing("toggle chain before help modifier")
        }
        return String(dashboard[toggle.lowerBound..<help.upperBound])
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

    private func range(of needle: String, in source: String) throws -> Range<String.Index> {
        guard let found = source.range(of: needle) else {
            throw SourceSliceError.missing(needle)
        }
        return found
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

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        let opener = source[start]
        let closer: Character = opener == "(" ? ")" : "}"
        var depth = 0
        var index = start
        while index < source.endIndex {
            let character = source[index]
            if character == opener { depth += 1 }
            if character == closer {
                depth -= 1
                if depth == 0 {
                    return String(source[start...index])
                }
            }
            index = source.index(after: index)
        }
        throw SourceSliceError.missing("balanced \(opener) for \(label)")
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
