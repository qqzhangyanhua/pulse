import XCTest
@testable import SamplingCore

/// Phase 22 source wiring. Linux SamplingCore does not compile Views or the VM.
/// These tests read Swift source. They do not draw SwiftUI, hover a tooltip,
/// move keyboard focus, or run VoiceOver. A passing read is not a Mac tooltip.
final class MemoryGrowthListHelpWiringSourceTests: XCTestCase {
    private let sentence = "完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期内存占用序列判断趋势。"
    private let sharedHelp = ".help(MemoryGrowthListCopy.help)"
    private let toggleCall = "title: MemoryRisingOnlyChrome.toggleTitle,"

    func testHelpLiteralIsOnlyTheStaticLet() throws {
        let model = try repoText("Pulse/Models/MemoryGrowthSignal.swift")
        let copy = try typeBody(named: "MemoryGrowthListCopy", keyword: "enum", in: model)
        XCTAssertEqual(occurrenceCount(of: "static let", in: copy), 2)
        XCTAssertEqual(
            try lineContaining("static let help", in: copy).trimmingCharacters(in: .whitespaces),
            "static let help = \"\(sentence)\""
        )
        XCTAssertEqual(
            try lineContaining("static let title", in: copy).trimmingCharacters(in: .whitespaces),
            "static let title = \"上涨\""
        )
        XCTAssertEqual(occurrenceCount(of: sentence, in: model), 1)

        let badgeType = try typeBody(named: "MemoryGrowthListBadge", keyword: "struct", in: model)
        XCTAssertTrue(badgeType.contains("let title: String"))
        XCTAssertTrue(badgeType.contains("let help: String"))
        XCTAssertEqual(occurrenceCount(of: "let ", in: badgeType), 2)

        let badge = try functionBody(named: "badge", in: model)
        XCTAssertTrue(badge.contains("title: MemoryGrowthListCopy.title"))
        XCTAssertTrue(badge.contains("help: MemoryGrowthListCopy.help"))
        XCTAssertFalse(badge.contains("help: \""))
        XCTAssertFalse(badge.contains(sentence))

        XCTAssertEqual(try productionHits(of: sentence), ["Models/MemoryGrowthSignal.swift:1"])
        XCTAssertEqual(
            try productionHits(of: "help: MemoryGrowthListCopy.help"),
            ["Models/MemoryGrowthSignal.swift:1"]
        )
    }

    func testRisingToggleHelpIsTheSharedIdentifier() throws {
        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        let code = stripLineComments(dashboard)
        XCTAssertEqual(
            occurrenceCount(of: sharedHelp, in: code),
            1,
            "Toggle help must be the identifier \(sharedHelp) exactly once"
        )
        XCTAssertEqual(try productionHits(of: sharedHelp), ["Views/MemoryDashboardView.swift:1"])
        XCTAssertFalse(code.contains(sentence), "the view must not carry a second literal")
        XCTAssertFalse(code.contains("risingOnlyFilter = false"))
        XCTAssertTrue(code.contains("ToolbarItemGroup(placement: .primaryAction)"))
        XCTAssertEqual(occurrenceCount(of: "MemoryRisingOnlyChrome.showsToggle(page: vm.selectedPage)", in: code), 1)
        XCTAssertEqual(occurrenceCount(of: toggleCall, in: code), 1)
        XCTAssertTrue(code.contains("MemoryToolbarSwitch("))
        XCTAssertFalse(code.contains(".toggleStyle(.switch)"))

        let toggleAt = try index(of: toggleCall, in: code)
        let fieldAt = try index(of: "AppFilterField(text: $vm.filter)", in: code)
        XCTAssertLessThan(toggleAt, fieldAt)

        let shows = try braceBody(after: "if MemoryRisingOnlyChrome.showsToggle(page: vm.selectedPage)", in: code)
        XCTAssertEqual(occurrenceCount(of: sharedHelp, in: shows), 1)
        XCTAssertEqual(occurrenceCount(of: toggleCall, in: shows), 1)
        XCTAssertFalse(shows.contains("AppFilterField"))

        XCTAssertEqual(
            compact(shows),
            "{MemoryToolbarSwitch(title:MemoryRisingOnlyChrome.toggleTitle,systemImage:\"chart.line.uptrend.xyaxis\",isOn:$vm.risingOnlyFilter).help(MemoryGrowthListCopy.help)}"
        )
        XCTAssertFalse(shows.contains(".disabled"))
        XCTAssertFalse(shows.contains(sentence))
    }

    func testBadgeRowReadsTheInstanceHelpOnlyWhenPresent() throws {
        let pane = try repoText("Pulse/Views/ProcessTablePane.swift")
        XCTAssertFalse(pane.contains(sentence))
        XCTAssertFalse(pane.contains("此上涨判断针对 PID"))
        XCTAssertFalse(pane.contains("MemoryGrowthListCopy"))
        XCTAssertTrue(pane.contains("vm.memoryGrowthListBadge(for: row.pid)"))
        XCTAssertTrue(pane.contains("groupedMemberCount: row.groupedMemberCount"))
        XCTAssertTrue(pane.contains("rowPid: row.pid"))
        XCTAssertFalse(pane.contains("rowPid: vm.selectedPid"))
        XCTAssertEqual(occurrenceCount(of: ".help(badge.help)", in: pane), 1)
        XCTAssertEqual(occurrenceCount(of: ".accessibilityHidden(true)", in: pane), 1)
        XCTAssertEqual(occurrenceCount(of: "parts.append(growthBadge.help)", in: pane), 1)
        XCTAssertEqual(occurrenceCount(of: ".accessibilityElement(children: .ignore)", in: pane), 1)

        let chip = try typeBody(named: "MemoryGrowthRisingBadge", keyword: "struct", in: pane)
        XCTAssertEqual(occurrenceCount(of: ".help(badge.help)", in: chip), 1)
        XCTAssertEqual(occurrenceCount(of: ".accessibilityHidden(true)", in: chip), 1)
        XCTAssertFalse(chip.contains(sentence))
        XCTAssertFalse(chip.contains(sharedHelp))

        let label = try functionBody(named: "accessibilityLabel", in: pane)
        XCTAssertEqual(occurrenceCount(of: "if let growthBadge", in: label), 1)
        XCTAssertEqual(occurrenceCount(of: "parts.append(growthBadge.help)", in: label), 1)
        let branch = try braceBody(after: "if let growthBadge", in: label)
        XCTAssertEqual(compact(branch), "{parts.append(growthBadge.help)}")
        let outside = label.replacingOccurrences(of: branch, with: "")
        XCTAssertFalse(outside.contains("growthBadge.help"))
        XCTAssertFalse(outside.contains(sentence))
    }

    func testDashboardVMDoesNotOwnTheHelpSentence() throws {
        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        XCTAssertFalse(vm.contains(sentence))
        XCTAssertFalse(vm.contains("MemoryGrowthListCopy"))
        XCTAssertEqual(occurrenceCount(of: "@Published", in: vm), 31, "battery card adds energyBatteryCard; energy page adds energyWindowRates; permission footnote adds processPermissionFootnote")
        XCTAssertEqual(occurrenceCount(of: "didSet", in: vm), 4)
        XCTAssertEqual(occurrenceCount(of: "@MainActor", in: vm), 1)
        let badge = try functionBody(named: "memoryGrowthListBadge", in: vm)
        XCTAssertTrue(compact(badge).contains("seriesByPid:topMemorySeries"))
        let sorted = try functionBody(named: "sortedRows", in: vm)
        XCTAssertTrue(compact(sorted).contains("AppGroupProjection.apply(rows:visibleRows"))
        XCTAssertFalse(sorted.contains("@Published"))
    }

    func testPackageAndProjectStayOnTheExistingModel() throws {
        let package = try repoText("Package.swift")
        XCTAssertEqual(occurrenceCount(of: "\"Models/MemoryGrowthSignal.swift\"", in: package), 1)
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))
        XCTAssertTrue(package.contains("\"Sampling/MemorySampler.swift\""))
        XCTAssertFalse(package.contains("MemoryDashboardView.swift"))
        XCTAssertFalse(package.contains("ProcessTablePane.swift"))
        XCTAssertFalse(package.contains("MemoryDashboardVM.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertEqual(occurrenceCount(of: "isa = PBXBuildFile;", in: project), 100, "adds MenuBarReading.swift, PulseSettingsView.swift, BatteryMath.swift, ProcessEnergy.swift, ProcessRowCopy.swift, PressureNotice.swift, PressureNoticeCenter.swift, LoginItem.swift, ProcessQuitRoute.swift, ProcessPermissionFootnote.swift, ProcessPermissionFootnoteLabel.swift, the four save-snapshot files, MemoryDetailAttribution.swift, ProcessDetailSidebar+MemoryAttribution.swift, MemoryMagnitudeVisibleGroup.swift, MemoryGroupRowHighlight.swift, MemoryGroupRowCopy.swift, MemoryRevealGroupRow.swift, TopCardRevealTarget.swift, Top3ProcessTap.swift, MemoryDashboardVM+Top3Tap.swift, ProcessTree.swift, ProcessTreeView.swift, ProcessEnergyWindow.swift, EnergyPage.swift, EnergyProcessTable.swift, EnergyBattery.swift, EnergyBatteryReader.swift, EnergyBatteryCardView.swift, MemoryDashboardVM+EnergyBattery.swift, and ProcessDetailSidebar+Energy.swift")
        let build = try markedSection("PBXBuildFile", in: project)
        let refs = try markedSection("PBXFileReference", in: project)
        let models = try modelsGroup(in: project)
        let sources = try markedSection("PBXSourcesBuildPhase", in: project)
        XCTAssertEqual(occurrenceCount(of: "MemoryGrowthSignal.swift in Sources", in: build), 1)
        XCTAssertEqual(occurrenceCount(of: "path = MemoryGrowthSignal.swift;", in: refs), 1)
        XCTAssertEqual(occurrenceCount(of: "MemoryGrowthSignal.swift", in: models), 1)
        XCTAssertEqual(occurrenceCount(of: "MemoryGrowthSignal.swift in Sources", in: sources), 1)
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

    private func productionHits(of needle: String) throws -> [String] {
        let root = repoRoot().appendingPathComponent("Pulse", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw SourceSliceError.missing("Pulse tree")
        }
        var hits: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let count = occurrenceCount(of: needle, in: text)
            if count == 0 { continue }
            let prefix = root.path + "/"
            guard url.path.hasPrefix(prefix) else {
                throw SourceSliceError.missing("relative path for \(url.path)")
            }
            let relative = String(url.path.dropFirst(prefix.count))
            hits.append("\(relative):\(count)")
        }
        return hits.sorted()
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

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound else {
            throw SourceSliceError.missing(needle)
        }
        guard let brace = source[start...].firstIndex(of: "{") else {
            throw SourceSliceError.missing("body after \(needle)")
        }
        return try balancedSlice(from: brace, in: source, label: needle)
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

    private func stripLineComments(_ source: String) -> String {
        source.components(separatedBy: .newlines).map { line -> String in
            guard let marker = line.range(of: "//") else { return line }
            return String(line[..<marker.lowerBound])
        }.joined(separator: "\n")
    }

    private func compact(_ source: String) -> String {
        stripLineComments(source).filter { !$0.isWhitespace }
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
