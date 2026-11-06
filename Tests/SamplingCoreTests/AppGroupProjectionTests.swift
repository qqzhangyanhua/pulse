import XCTest
@testable import SamplingCore

final class AppGroupProjectionTests: XCTestCase {
    func testOffReturnsTheSameRows() {
        let rows = [row(1, "Chrome", memory: 10), row(2, "Chrome", memory: 30)]
        XCTAssertEqual(AppGroupProjection.apply(rows: rows, grouped: false), rows)
        XCTAssertFalse(AppGroupChrome.showsToggle(page: .cpu))
        XCTAssertTrue(AppGroupChrome.showsToggle(page: .memory))
        XCTAssertEqual(AppGroupChrome.toggleTitle, "按 App")
    }

    func testGroupSumsMemoryAndThreadsAndKeepsTheHeaviestPid() {
        let rows = [
            row(2, "Chrome", memory: 10, threads: 2, cpu: 1),
            row(5, "Notes", memory: 4, threads: 1, cpu: 0),
            row(9, "Chrome", memory: 30, threads: 4, cpu: 2),
        ]
        let grouped = AppGroupProjection.apply(rows: rows, grouped: true)
        XCTAssertEqual(grouped.map(\.pid), [9, 5])
        let chrome = grouped[0]
        XCTAssertEqual(chrome.memoryBytes, 40)
        XCTAssertEqual(chrome.threadCount, 6)
        XCTAssertEqual(chrome.cpuPercent, 3)
        XCTAssertEqual(chrome.name, "Chrome")
    }

    func testEqualMemoryKeepsTheSmallerPid() {
        let grouped = AppGroupProjection.combine([
            row(8, "Helper", memory: 10),
            row(3, "Helper", memory: 10),
        ])
        XCTAssertEqual(grouped.pid, 3)
        XCTAssertEqual(grouped.memoryBytes, 20)
    }

    func testMissingRateStaysMissingAndZeroStillAdds() {
        let missing = AppGroupProjection.combine([
            row(1, "Chrome", memory: 1, cpu: nil, diskRead: 4),
            row(2, "Chrome", memory: 1, cpu: 1, diskRead: nil),
        ])
        XCTAssertNil(missing.cpuPercent)
        XCTAssertNil(missing.diskReadBytesPerSecond)
        XCTAssertNil(missing.diskWriteBytesPerSecond)

        let zero = AppGroupProjection.sum([0, 2])
        XCTAssertEqual(zero, 2)
        XCTAssertNil(AppGroupProjection.sum([0, nil]))
    }

    func testSelectionMovesToTheLeadOnlyWhileGrouped() {
        let rows = [row(2, "Chrome", memory: 10), row(9, "Chrome", memory: 30)]
        XCTAssertEqual(AppGroupProjection.selectedPid(current: 2, rows: rows, grouped: true), 9)
        XCTAssertEqual(AppGroupProjection.selectedPid(current: 9, rows: rows, grouped: false), 9)
        XCTAssertEqual(AppGroupProjection.selectedPid(current: 2, rows: rows, grouped: false), 2)
        XCTAssertNil(AppGroupProjection.selectedPid(current: nil, rows: rows, grouped: true))
    }

    func testCrownCardAndMenuBarStayUngrouped() throws {
        let overview = try source("Pulse/Views/OverviewSection.swift")
        XCTAssertTrue(overview.contains("TopConsumer.leading(in: vm.rows)"))
        XCTAssertFalse(overview.contains("AppGroupProjection"))

        let vm = try source("Pulse/ViewModels/MemoryDashboardVM.swift")
        let sorted = try functionBody(named: "sortedRows", in: vm)
        XCTAssertTrue(sorted.contains("AppGroupProjection.apply(rows: visibleRows"))
        XCTAssertTrue(sorted.contains("grouped: groupedByApp && selectedPage == .memory"))
        let menu = try functionBody(named: "menuBarPopover", in: vm)
        XCTAssertFalse(menu.contains("groupedByApp"))
        XCTAssertFalse(menu.contains("AppGroupProjection"))

        let sampler = try source("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("AppGroupProjection"))
        XCTAssertFalse(sampler.contains("groupedByApp"))

        let dashboard = try source("Pulse/Views/MemoryDashboardView.swift")
        XCTAssertTrue(dashboard.contains("Toggle(AppGroupChrome.toggleTitle, isOn: $vm.groupedByApp)"))
        let windowed = try XCTUnwrap(dashboard.range(of: "WindowedAppChrome.toggleTitle"))
        let grouped = try XCTUnwrap(dashboard.range(of: "AppGroupChrome.toggleTitle"))
        let rising = try XCTUnwrap(dashboard.range(of: "MemoryRisingOnlyChrome.toggleTitle"))
        XCTAssertLessThan(windowed.lowerBound, grouped.lowerBound)
        XCTAssertLessThan(grouped.lowerBound, rising.lowerBound)
    }

    private func row(
        _ pid: Int32,
        _ name: String,
        memory: UInt64,
        threads: Int = 1,
        cpu: Double? = nil,
        diskRead: Double? = nil
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: cpu,
            memoryBytes: memory,
            threadCount: threads,
            diskReadBytesPerSecond: diskRead,
            diskWriteBytesPerSecond: nil
        )
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        guard let range = source.range(of: "var \(name):"),
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
                if depth == 0 { return String(source[brace...index]) }
            }
            index = source.index(after: index)
        }
        return ""
    }
}
