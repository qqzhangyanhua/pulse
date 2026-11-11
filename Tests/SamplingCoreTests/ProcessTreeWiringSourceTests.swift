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
        XCTAssertTrue(sidebar.contains("selectPidIfPresent"))
        XCTAssertTrue(sidebar.contains("showsProcessTreeButton"))
        XCTAssertTrue(sidebar.contains("onSelect:"))
        XCTAssertFalse(sidebar.contains("selectedPid ="))
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
