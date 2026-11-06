import XCTest
@testable import SamplingCore

final class ProcessGlossaryTests: XCTestCase {
    func testKnownNamesReturnOneCalmSentence() {
        XCTAssertGreaterThanOrEqual(ProcessGlossary.notes.count, 30)
        XCTAssertEqual(ProcessGlossary.note(for: "WindowServer"), "把窗口画到屏幕上。")
        XCTAssertEqual(ProcessGlossary.note(for: " kernel_task "), ProcessGlossary.notes["kernel_task"])
        XCTAssertNil(ProcessGlossary.note(for: "Chrome"))
        XCTAssertNil(ProcessGlossary.note(for: "   "))
        XCTAssertNil(ProcessGlossary.note(for: ""))
        XCTAssertFalse(ProcessGlossary.notes.values.contains("未知"))
    }

    func testNotesOmitBannedWords() {
        let banned = ["泄漏", "泄露", "leak", "危险", "告警", "异常", "独占", "可释放", "活动监视器", "真实占用", "footprint"]
        let blob = ProcessGlossary.notes.values.joined(separator: "\n")
        for word in banned {
            XCTAssertFalse(blob.localizedCaseInsensitiveContains(word), word)
        }
    }

    func testSidebarShowsTheNoteAndTheListDoesNot() throws {
        let sidebar = try source("Pulse/Views/ProcessDetailSidebar.swift")
        XCTAssertTrue(sidebar.contains("ProcessGlossary.note(for: detail.row.name)"))
        XCTAssertFalse(sidebar.contains("未知"))

        let list = try source("Pulse/Views/ProcessTablePane.swift")
        XCTAssertFalse(list.contains("ProcessGlossary"))

        let growth = try source("Pulse/Models/MemoryGrowthSignal.swift")
        let help = growth.range(of: "static let help")
        XCTAssertNotNil(help)
        XCTAssertFalse(growth.contains("ProcessGlossary"))
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
