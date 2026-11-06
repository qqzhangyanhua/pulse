import XCTest
@testable import SamplingCore

/// Phase 20 pure plan. These tests call `TopAppLocation.plan` and the existing
/// `MemoryGrowthRisingFilter.ordered`. They do not compile `MemoryDashboardVM`
/// and do not choose a representative with a new tie rule. Pid 43 is the input
/// read off today's `>=` row order: two Chrome rows of 3 GiB sum to 6 GiB,
/// the later row stays the representative, and Safari's 5 GiB is smaller.
final class TopAppLocationTests: XCTestCase {
    private let gib: UInt64 = 1_073_741_824
    private let helperPid: Int32 = 77

    func testSafariRisingOnPlansChrome43WithoutRedefiningTheTie() {
        let rows = chromeFixture()
        let chrome = rows.filter { $0.name == "Chrome" }
        XCTAssertEqual(chrome.map(\.pid), [42, 43])
        XCTAssertEqual(chrome.map(\.memoryBytes), [3 * gib, 3 * gib])
        XCTAssertEqual(chrome.reduce(UInt64(0)) { $0 &+ $1.memoryBytes }, 6 * gib)
        XCTAssertEqual(chrome.count, 2)
        XCTAssertEqual(3 * gib, 3_221_225_472)
        XCTAssertEqual(5 * gib, 5_368_709_120)
        XCTAssertEqual(6 * gib, 6_442_450_944)

        let plan = locate(name: "Chrome", pid: 43, rows: rows, currentFilter: "Safari", currentRisingOnly: true)
        XCTAssertEqual(plan?.nameFilter, .replace("Chrome"))
        XCTAssertEqual(plan?.risingOnly, false)
        XCTAssertEqual(plan?.acceptedPid, 43)
        XCTAssertEqual(plan?.reveal.pid, 43)
        XCTAssertEqual(plan?.reveal.generation, 1)
        XCTAssertNotEqual(plan?.acceptedPid, 42)

        let projected = ordered(rows, query: "Chrome", risingOnly: false)
        XCTAssertEqual(projected.filter { $0.name == "Chrome" }.map(\.pid), [42, 43])
        XCTAssertTrue(projected.contains { $0.name == "Chrome Helper" })
        XCTAssertFalse(projected.contains { $0.pid == 9 })
    }

    func testRisingOffMatchesOnWhenTheCallerPassesTheSamePreviousReveal() {
        let rows = chromeFixture()
        let previous = TopAppLocation.Reveal(pid: 43, generation: 8)
        let on = locate(
            name: "Chrome",
            pid: 43,
            rows: rows,
            currentFilter: "Safari",
            currentRisingOnly: true,
            previousReveal: previous
        )
        let off = locate(
            name: "Chrome",
            pid: 43,
            rows: rows,
            currentFilter: "Safari",
            currentRisingOnly: false,
            previousReveal: previous
        )
        XCTAssertEqual(on, off)
        XCTAssertEqual(on?.risingOnly, false)
        XCTAssertEqual(on?.nameFilter, .replace("Chrome"))
        XCTAssertEqual(on?.reveal, TopAppLocation.Reveal(pid: 43, generation: 9))
    }

    func testExactChromeQueryKeepsThatRawAndStillReveals() {
        let raw = "Chrome"
        let plan = locate(
            name: "Chrome",
            pid: 43,
            rows: chromeFixture(),
            currentFilter: raw,
            currentRisingOnly: true
        )
        XCTAssertEqual(raw, "Chrome")
        XCTAssertEqual(plan?.nameFilter, .keep)
        XCTAssertNotEqual(plan?.nameFilter, .replace("Chrome"))
        XCTAssertEqual(plan?.risingOnly, false)
        XCTAssertEqual(plan?.acceptedPid, 43)
        XCTAssertEqual(plan?.reveal.pid, 43)
        XCTAssertEqual(plan?.reveal.generation, 1)
    }

    func testBlankRawOffKeepsTheOriginalString() {
        let rows = chromeFixture()
        for raw in ["", " \n\t "] {
            let plan = locate(
                name: "Chrome",
                pid: 43,
                rows: rows,
                currentFilter: raw,
                currentRisingOnly: false
            )
            XCTAssertEqual(plan?.nameFilter, .keep, raw)
            XCTAssertNotEqual(plan?.nameFilter, .replace("Chrome"), raw)
            XCTAssertEqual(plan?.risingOnly, false, raw)
            XCTAssertEqual(plan?.acceptedPid, 43, raw)
            XCTAssertEqual(plan?.reveal, TopAppLocation.Reveal(pid: 43, generation: 1), raw)
            XCTAssertEqual(raw, raw.isEmpty ? "" : " \n\t ")
            let projected = ordered(rows, query: raw, risingOnly: false)
            XCTAssertTrue(projected.contains { $0.pid == 43 }, raw)
            XCTAssertTrue(projected.contains { $0.pid == 9 }, raw)
        }
    }

    func testBlankRawOnKeepsTheOriginalAndShowsThePidOnlyAfterRisingIsOff() {
        let rows = chromeFixture()
        let raw = " \n "
        let plan = locate(
            name: "Chrome",
            pid: 43,
            rows: rows,
            currentFilter: raw,
            currentRisingOnly: true
        )
        XCTAssertEqual(raw, " \n ")
        XCTAssertEqual(plan?.nameFilter, .keep)
        XCTAssertEqual(plan?.risingOnly, false)
        XCTAssertEqual(plan?.acceptedPid, 43)
        XCTAssertEqual(plan?.reveal.pid, 43)
        XCTAssertNotNil(plan?.reveal)

        let hidden = ordered(rows, query: raw, risingOnly: true)
        XCTAssertFalse(hidden.contains { $0.pid == 43 })
        let shown = ordered(rows, query: raw, risingOnly: false)
        XCTAssertTrue(shown.contains { $0.pid == 43 })
        XCTAssertTrue(shown.contains { $0.pid == 9 })
    }

    func testAlreadyPresentPidStillReplacesAndStaysInTheOrderedProjection() {
        let rows = chromeFixture()
        let previous = TopAppLocation.Reveal(pid: 43, generation: 2)
        let plan = locate(
            name: "Chrome",
            pid: 43,
            rows: rows,
            currentFilter: "Safari",
            currentRisingOnly: false,
            previousReveal: previous
        )
        XCTAssertEqual(plan?.nameFilter, .replace("Chrome"))
        XCTAssertEqual(plan?.risingOnly, false)
        XCTAssertEqual(plan?.acceptedPid, 43)
        XCTAssertEqual(plan?.reveal, TopAppLocation.Reveal(pid: 43, generation: 3))
        XCTAssertTrue(ordered(rows, query: "Chrome", risingOnly: false).contains { $0.pid == 43 })
    }

    func testMissingPidIsNilAndDoesNotConsumeGeneration() {
        let rows = chromeFixture().filter { $0.pid != 43 }
        XCTAssertTrue(rows.contains { $0.pid == 42 && $0.name == "Chrome" })
        let previous = TopAppLocation.Reveal(pid: 43, generation: 9)
        let missing = locate(
            name: "Chrome",
            pid: 43,
            rows: rows,
            currentFilter: "Safari",
            currentRisingOnly: true,
            previousReveal: previous
        )
        XCTAssertNil(missing)
        XCTAssertEqual(previous.generation, 9)

        let later = locate(
            name: "Chrome",
            pid: 43,
            rows: chromeFixture(),
            currentFilter: "Safari",
            currentRisingOnly: false,
            previousReveal: previous
        )
        XCTAssertEqual(later?.reveal.generation, 10)
        XCTAssertEqual(later?.acceptedPid, 43)
        XCTAssertNotEqual(later?.acceptedPid, 42)
    }

    func testRenamedPidIsNilAndDoesNotConsumeGeneration() {
        let rows = chromeFixture().map { row in
            row.pid == 43 ? process(pid: 43, name: "Chromium", memory: row.memoryBytes) : row
        }
        XCTAssertTrue(rows.contains { $0.pid == 42 && $0.name == "Chrome" })
        XCTAssertEqual(rows.first { $0.pid == 43 }?.name, "Chromium")
        let previous = TopAppLocation.Reveal(pid: 43, generation: 4)
        let renamed = locate(
            name: "Chrome",
            pid: 43,
            rows: rows,
            currentFilter: "",
            currentRisingOnly: false,
            previousReveal: previous
        )
        XCTAssertNil(renamed)
        XCTAssertEqual(previous.generation, 4)

        let later = locate(
            name: "Chrome",
            pid: 43,
            rows: chromeFixture(),
            currentFilter: "Safari",
            previousReveal: previous
        )
        XCTAssertEqual(later?.reveal.generation, 5)
        XCTAssertEqual(later?.acceptedPid, 43)
    }

    func testExactNameRejectsChromeHelperWhileTheExistingSubstringKeepsIt() {
        let rows = chromeFixture()
        let previous = TopAppLocation.Reveal(pid: 43, generation: 6)
        let helper = locate(
            name: "Chrome",
            pid: helperPid,
            rows: rows,
            currentFilter: "Chrome",
            currentRisingOnly: false,
            previousReveal: previous
        )
        XCTAssertNil(helper)
        XCTAssertNotEqual(rows.first { $0.pid == helperPid }?.name, "Chrome")

        let exact = locate(
            name: "Chrome",
            pid: 43,
            rows: rows,
            currentFilter: "Safari",
            currentRisingOnly: true,
            previousReveal: previous
        )
        XCTAssertEqual(exact?.acceptedPid, 43)
        XCTAssertEqual(exact?.reveal.generation, 7)
        let projected = ordered(rows, query: "Chrome", risingOnly: false)
        XCTAssertTrue(projected.contains { $0.name == "Chrome Helper" })
        XCTAssertTrue(projected.contains { $0.pid == 43 && $0.name == "Chrome" })
        XCTAssertFalse(projected.contains { $0.name == "Safari" })
    }

    func testNonMemoryPageIsNilAndDoesNotConsumeGeneration() {
        let rows = chromeFixture()
        let previous = TopAppLocation.Reveal(pid: 43, generation: 3)
        for page in DashboardPage.allCases where page != .memory {
            let plan = locate(
                name: "Chrome",
                pid: 43,
                rows: rows,
                page: page,
                currentFilter: "",
                currentRisingOnly: true,
                previousReveal: previous
            )
            XCTAssertNil(plan, "\(page)")
        }
        let memory = locate(
            name: "Chrome",
            pid: 43,
            rows: rows,
            page: .memory,
            currentFilter: "",
            previousReveal: previous
        )
        XCTAssertEqual(memory?.reveal.generation, 4)
        XCTAssertEqual(memory?.nameFilter, .keep)
    }

    func testLookalikeRawReplacesAndGenerationUsesOverflowAdd() {
        let rows = chromeFixture()
        for raw in [" Chrome", "Chrome ", "Chrome\n", "chrome", "\tChrome"] {
            let plan = locate(name: "Chrome", pid: 43, rows: rows, currentFilter: raw)
            XCTAssertEqual(plan?.nameFilter, .replace("Chrome"), raw)
            XCTAssertNotEqual(raw, "Chrome", raw)
        }
        let wrapped = locate(
            name: "Chrome",
            pid: 43,
            rows: rows,
            currentFilter: "Safari",
            previousReveal: TopAppLocation.Reveal(pid: 43, generation: UInt64.max)
        )
        XCTAssertEqual(wrapped?.reveal.generation, UInt64.max &+ 1)
        XCTAssertEqual(wrapped?.reveal.generation, 0)
        XCTAssertEqual(wrapped?.reveal.pid, 43)
    }

    func testRepeatedPidUsesTheFirstRowNameOnly() {
        let rows = [
            process(pid: 43, name: "Safari", memory: gib),
            process(pid: 43, name: "Chrome", memory: 3 * gib),
        ]
        XCTAssertNil(locate(name: "Chrome", pid: 43, rows: rows, currentFilter: "Safari"))
        let first = locate(name: "Safari", pid: 43, rows: rows, currentFilter: "Safari")
        XCTAssertEqual(first?.acceptedPid, 43)
        XCTAssertEqual(first?.nameFilter, .keep)
        XCTAssertEqual(first?.reveal.generation, 1)
    }

    func testPlanSourceDoesNotRecomputeTopOrReadSelection() throws {
        let source = try String(contentsOf: modelURL(), encoding: .utf8)
        for token in ["TopConsumer", "leading", "selectedPid", "tableSort", "ProcessTableSort"] {
            XCTAssertFalse(source.contains(token), token)
        }
        XCTAssertTrue(source.contains("_ = currentRisingOnly"))
        XCTAssertFalse(source.contains("!name.isEmpty"))
        let plan = try structBody(named: "Plan", in: source)
        XCTAssertFalse(plan.contains("sort"))
    }

    private func locate(
        name: String,
        pid: Int32,
        rows: [ProcessRow],
        page: DashboardPage = .memory,
        currentFilter: String,
        currentRisingOnly: Bool = false,
        previousReveal: TopAppLocation.Reveal? = nil
    ) -> TopAppLocation.Plan? {
        TopAppLocation.plan(
            name: name,
            pid: pid,
            rows: rows,
            page: page,
            currentFilter: currentFilter,
            currentRisingOnly: currentRisingOnly,
            previousReveal: previousReveal
        )
    }

    private func ordered(
        _ rows: [ProcessRow],
        query: String,
        risingOnly: Bool
    ) -> [ProcessRow] {
        MemoryGrowthRisingFilter.ordered(
            rows: rows,
            nameQuery: query,
            page: .memory,
            risingOnly: risingOnly,
            seriesByPid: [:],
            sort: ProcessTableSort.defaultSort(for: .memory)
        )
    }

    private func chromeFixture() -> [ProcessRow] {
        [
            process(pid: 42, name: "Chrome", memory: 3 * gib),
            process(pid: 43, name: "Chrome", memory: 3 * gib),
            process(pid: 9, name: "Safari", memory: 5 * gib),
            process(pid: helperPid, name: "Chrome Helper", memory: gib),
        ]
    }

    private func process(pid: Int32, name: String, memory: UInt64) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: memory,
            threadCount: 1
        )
    }

    private func modelURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Pulse/Models/TopAppLocation.swift")
    }

    private func structBody(named name: String, in source: String) throws -> String {
        guard let start = source.range(of: "struct \(name)")?.lowerBound,
              let brace = source[start...].firstIndex(of: "{")
        else {
            throw PlanSourceError.missing(name)
        }
        var depth = 0
        var index = brace
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[brace...index])
                }
            }
            index = source.index(after: index)
        }
        throw PlanSourceError.missing(name)
    }
}

private enum PlanSourceError: Error {
    case missing(String)
}
