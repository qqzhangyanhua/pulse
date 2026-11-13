import XCTest

final class ProcessTreeWiringSourceTests: XCTestCase {
    func testSidebarOpensTheProcessTreeWithoutASecondDisclosureOrDismiss() throws {
        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        XCTAssertTrue(sidebar.contains("arrow.triangle.branch"))
        XCTAssertTrue(sidebar.contains("进程树"))
        XCTAssertTrue(sidebar.contains("showsProcessTree"))
        XCTAssertEqual(occurrenceCount(of: "DisclosureGroup(", in: sidebar), 1)
        XCTAssertEqual(occurrenceCount(of: "vm.dismissSidebar()", in: sidebar), 1)

        let view = try repoText("Pulse/Views/ProcessTreeView.swift")
        XCTAssertTrue(view.contains("返回"))
        XCTAssertTrue(view.contains("chevron.left"))
        XCTAssertFalse(view.contains("DisclosureGroup("))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ProcessTreeView.swift"))
        XCTAssertTrue(project.contains("path = ProcessTreeView.swift;"))

        let package = try repoText("Package.swift")
        XCTAssertFalse(package.contains("ProcessTreeView.swift"))
    }

    func testNonPlaceholderTapSelectsAndGroupingHidesTheButton() throws {
        let view = try repoText("Pulse/Views/ProcessTreeView.swift")
        let placeholder = try XCTUnwrap(view.range(of: "placeholderText()")?.lowerBound)
        XCTAssertTrue(
            view[..<placeholder].contains("onSelect("),
            "non-placeholder name tap calls onSelect"
        )
        XCTAssertFalse(
            view[placeholder...].contains("onSelect"),
            "placeholder does not call onSelect"
        )
        XCTAssertFalse(view.contains("memoryBytes: 0"))

        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        XCTAssertTrue(sidebar.contains("showsProcessTreeButton"))
        XCTAssertTrue(sidebar.contains("onSelect:"))
        XCTAssertTrue(sidebar.contains("vm.focusProcessFromTree(centerPid); showsProcessTree = false"))
        XCTAssertTrue(sidebar.contains("vm.focusProcessFromTree(pid); showsProcessTree = false"))
        XCTAssertEqual(occurrenceCount(of: "focusProcessFromTree", in: sidebar), 2)
        XCTAssertLessThan(
            try index(of: "vm.focusProcessFromTree(centerPid)", in: sidebar),
            try index(of: "vm.focusProcessFromTree(pid)", in: sidebar)
        )
        XCTAssertFalse(sidebar.contains("selectPidIfPresent"))
        XCTAssertFalse(sidebar.contains("selectedPid ="))

        let focus = try functionBody(
            named: "focusProcessFromTree",
            in: try repoText("Pulse/Models/DashboardCore+TopAppLocation.swift")
        )
        XCTAssertTrue(focus.contains("select(pid:"))
        XCTAssertFalse(focus.contains("selectedPid ="))
        XCTAssertFalse(focus.contains("filter ="))
        XCTAssertFalse(focus.contains("groupedByApp"))
        XCTAssertLessThan(
            try index(of: "filtersAfterFocus", in: focus),
            try index(of: "select(pid:", in: focus)
        )
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
        guard let range = source.range(of: "func \(name)("),
              let brace = source[range.lowerBound...].firstIndex(of: "{")
        else {
            XCTFail("missing \(name)")
            return ""
        }
        var depth = 0
        var index = brace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[brace...index])
                }
            }
            index = source.index(after: index)
        }
        XCTFail("unbalanced \(name)")
        return ""
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            XCTFail("missing \(needle)")
            return source.endIndex
        }
        return found
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var search = haystack.startIndex
        while let found = haystack.range(of: needle, range: search..<haystack.endIndex) {
            count += 1
            search = found.upperBound
        }
        return count
    }
}
