import XCTest
@testable import SamplingCore

final class AppGroupProjectionTests: XCTestCase {
    func testOffReturnsTheSameRows() {
        let rows = [row(1, "Chrome", memory: 10), row(2, "Chrome", memory: 30)]
        XCTAssertEqual(AppGroupProjection.apply(rows: rows, grouped: false), rows)
        XCTAssertEqual(AppGroupChrome.toggleTitle, "按 App")
        XCTAssertTrue(AppGroupChrome.applies(on: .memory))
        XCTAssertTrue(AppGroupChrome.applies(on: .cpu))
        XCTAssertFalse(AppGroupChrome.applies(on: .disk))
        XCTAssertFalse(AppGroupChrome.applies(on: .network))
        XCTAssertFalse(AppGroupChrome.applies(on: .gpu))
        XCTAssertFalse(AppGroupChrome.applies(on: .machine))
        for page in DashboardPage.allCases {
            XCTAssertEqual(
                AppGroupChrome.showsToggle(page: page),
                AppGroupChrome.applies(on: page),
                "\(page)"
            )
        }
        XCTAssertEqual(AppGroupChrome.help, "同名进程合为一行。内存、线程、CPU、能耗和唤醒相加。")
        XCTAssertFalse(AppGroupChrome.help.contains("磁盘"))
        XCTAssertFalse(AppGroupChrome.help.contains("网络"))
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

    func testAnyResidentMemberMarksTheCombinedRowResidentAndKeepsTheSum() {
        let grouped = AppGroupProjection.combine([
            row(4, "WeChat", memory: 800),
            row(7, "WeChat", memory: 200, source: .resident),
        ])
        XCTAssertEqual(grouped.memoryBytes, 1_000)
        XCTAssertEqual(grouped.memorySource, .resident)
    }

    func testAllFootprintMembersKeepFootprintOnTheCombinedRow() {
        let grouped = AppGroupProjection.combine([
            row(4, "WeChat", memory: 800),
            row(7, "WeChat", memory: 200),
        ])
        XCTAssertEqual(grouped.memoryBytes, 1_000)
        XCTAssertEqual(grouped.memorySource, .footprint)
        XCTAssertFalse(grouped.residentMemoryIsPartial)
    }

    func testAnyResidentMemberMarksPartialIncludingAOneMemberGroup() {
        let mixed = AppGroupProjection.combine([
            row(4, "WeChat", memory: 800),
            row(7, "WeChat", memory: 200, source: .resident),
        ])
        XCTAssertTrue(mixed.residentMemoryIsPartial)

        let allResident = AppGroupProjection.combine([
            row(1, "Mail", memory: 10, source: .resident),
            row(2, "Mail", memory: 30, source: .resident),
        ])
        XCTAssertEqual(allResident.memoryBytes, 40)
        XCTAssertEqual(allResident.memorySource, .resident)
        XCTAssertTrue(allResident.residentMemoryIsPartial)

        let alone = AppGroupProjection.combine([
            row(4, "WeChat", memory: 800, source: .resident),
        ])
        XCTAssertEqual(alone.memoryBytes, 800)
        XCTAssertEqual(alone.memorySource, .resident)
        XCTAssertTrue(alone.residentMemoryIsPartial)

        let grouped = AppGroupProjection.apply(
            rows: [row(4, "WeChat", memory: 800, source: .resident)],
            grouped: true
        )
        XCTAssertEqual(grouped.map(\.memoryBytes), [800])
        XCTAssertEqual(grouped.map(\.memorySource), [.resident])
        XCTAssertEqual(grouped.map(\.residentMemoryIsPartial), [true])

        let aloneFootprint = AppGroupProjection.combine([
            row(5, "Notes", memory: 100),
        ])
        XCTAssertEqual(aloneFootprint.memorySource, .footprint)
        XCTAssertFalse(aloneFootprint.residentMemoryIsPartial)

        let ungrouped = AppGroupProjection.apply(
            rows: [row(4, "WeChat", memory: 800, source: .resident)],
            grouped: false
        )
        XCTAssertEqual(ungrouped.map(\.memorySource), [.resident])
        XCTAssertEqual(ungrouped.map(\.residentMemoryIsPartial), [false])
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
        let groupedCall = "grouped: groupedByApp && AppGroupChrome.applies(on: selectedPage)"
        XCTAssertTrue(sorted.contains("AppGroupProjection.apply(rows: visibleRows"))
        XCTAssertTrue(sorted.contains(groupedCall))
        XCTAssertFalse(sorted.contains("selectedPage == .memory"))
        let quit = try source("Pulse/ViewModels/MemoryDashboardVM+QuitSession.swift")
        let selection = try functionBody(named: "applyGroupedByAppSelection", in: quit)
        XCTAssertTrue(selection.contains(groupedCall))
        XCTAssertFalse(selection.contains("selectedPage == .memory"))
        let menu = try functionBody(named: "menuBarPopover", in: vm)
        XCTAssertFalse(menu.contains("groupedByApp"))
        XCTAssertFalse(menu.contains("AppGroupProjection"))

        let sampler = try source("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("AppGroupProjection"))
        XCTAssertFalse(sampler.contains("groupedByApp"))

        let dashboard = try source("Pulse/Views/MemoryDashboardView.swift")
        XCTAssertTrue(dashboard.contains("title: AppGroupChrome.toggleTitle,"))
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
        diskRead: Double? = nil,
        source: ProcessMemorySource = .footprint
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: cpu,
            memoryBytes: memory,
            memorySource: source,
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
        let patterns = ["var \(name):", "func \(name)("]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
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
        }
        XCTFail("missing \(name)")
        return ""
    }
}
