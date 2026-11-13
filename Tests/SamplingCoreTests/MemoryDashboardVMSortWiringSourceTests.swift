import XCTest
@testable import SamplingCore

/// Phase 14 step 2: structural check of `MemoryDashboardVM.swift` source.
///
/// Linux SamplingCore excludes `ViewModels`. This does **not** instantiate
/// `MemoryDashboardVM`, does not compile that target, and does not run the
/// MainActor / Xcode / menu-bar GUI path. Passing here is not a VM behavior test.
final class MemoryDashboardVMSortWiringSourceTests: XCTestCase {
    func testPackageStillExcludesViewModelsFromLinuxSamplingCore() throws {
        let package = try String(contentsOf: repoFile("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains("\"ViewModels\""), "Linux target must keep excluding ViewModels")
        XCTAssertTrue(package.contains("\"Sampling/MemorySampler.swift\""))
        XCTAssertFalse(
            package.contains("MemoryDashboardVM.swift"),
            "do not drag the VM into the Linux target"
        )
    }

    /// Phase 19 source read. Not a GUI test: it does not instantiate
    /// `MemoryDashboardVM`, does not compile the app, and does not click a header.
    func testPhase19DiskHeadersAreLiteralColumnsAndThisIsNotGUI() throws {
        let pane = try String(contentsOf: repoFile("Pulse/Views/ProcessTablePane.swift"), encoding: .utf8)
        let readHeader = "sortHeader(ProcessColumnTitle.diskRead, column: .diskRead, trailing: true)"
        let writeHeader = "sortHeader(ProcessColumnTitle.diskWrite, column: .diskWrite, trailing: true)"
        XCTAssertEqual(occurrenceCount(of: readHeader, in: pane), 1)
        XCTAssertEqual(occurrenceCount(of: writeHeader, in: pane), 1)
        XCTAssertFalse(pane.contains("column: .disk,"))
        XCTAssertFalse(pane.contains("column: .disk)"))

        let columnHeader = try functionBody(named: "columnHeader", in: pane)
        XCTAssertTrue(columnHeader.contains(readHeader))
        XCTAssertTrue(columnHeader.contains(writeHeader))
        XCTAssertTrue(columnHeader.contains("staticHeader(ProcessColumnTitle.network)"))
        XCTAssertFalse(columnHeader.contains("sortHeader(ProcessColumnTitle.network"))

        let sortHeader = try functionBody(named: "sortHeader", in: pane)
        XCTAssertTrue(sortHeader.contains("let active = vm.tableSort.column == column"))
        XCTAssertTrue(sortHeader.contains("vm.setTableSort(vm.tableSort.selecting(column))"))
        XCTAssertTrue(sortHeader.contains("vm.tableSort.descending ? \"chevron.down\" : \"chevron.up\""))
        XCTAssertFalse(sortHeader.contains("diskRead"))
        XCTAssertFalse(sortHeader.contains("diskWrite"))
        XCTAssertFalse(sortHeader.contains("click"))

        let vm = try vmSource()
        for line in vm.components(separatedBy: .newlines) where line.contains("@Published") {
            XCTAssertFalse(line.contains("diskRead"), line)
            XCTAssertFalse(line.contains("diskWrite"), line)
            XCTAssertFalse(line.contains("lastMemorySort"), line)
        }

        let model = try String(contentsOf: repoFile("Pulse/Models/CPUPage.swift"), encoding: .utf8)
        let compare = try functionBody(named: "compare", in: model)
        XCTAssertTrue(compare.contains("compareDoubles(lhs.diskSortKey, rhs.diskSortKey)"))
        XCTAssertTrue(compare.contains("lhs.diskReadBytesPerSecond ?? -1"))
        XCTAssertTrue(compare.contains("rhs.diskReadBytesPerSecond ?? -1"))
        XCTAssertTrue(compare.contains("lhs.diskWriteBytesPerSecond ?? -1"))
        XCTAssertTrue(compare.contains("rhs.diskWriteBytesPerSecond ?? -1"))
        for forbidden in ["ProcessDetail", "frozenDetail", "selectedPid", "sampler", "DiskRateText"] {
            XCTAssertFalse(compare.contains(forbidden), forbidden)
        }
        let ordered = try functionBody(named: "ordered", in: model)
        XCTAssertTrue(ordered.contains("lhs.pid < rhs.pid"))
        for forbidden in ["ProcessNameFilter", "MemoryGrowthRisingFilter", "selectedPid", "risingOnly", "sample("] {
            XCTAssertFalse(ordered.contains(forbidden), forbidden)
        }

        let rows = try String(contentsOf: repoFile("Pulse/Models/MemoryModels.swift"), encoding: .utf8)
        let diskSortKey = try functionBody(named: "diskSortKey", in: rows)
        XCTAssertTrue(
            diskSortKey.contains(
                "guard let diskReadBytesPerSecond, let diskWriteBytesPerSecond else { return -1 }"
            )
        )
        XCTAssertTrue(diskSortKey.contains("return diskReadBytesPerSecond + diskWriteBytesPerSecond"))
    }

    private func vmSource() throws -> String {
        try WiringSourceText.text(for: "MemoryDashboardVM")
    }

    private func repoFile(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = [
            "var \(name):",
            "func \(name)(",
            "func \(name)()",
            "private func \(name)(",
            "private func \(name)()",
        ]
        var start: String.Index?
        for pattern in patterns {
            if let range = source.range(of: pattern) {
                start = range.lowerBound
                break
            }
        }
        guard let start else {
            throw SourceSliceError.missing("declaration for \(name)")
        }
        guard let brace = source[start...].firstIndex(of: "{") else {
            throw SourceSliceError.missing("body for \(name)")
        }
        return try balancedSlice(from: brace, in: source, label: name)
    }

    private func projectCall(in popover: String) throws -> String {
        guard let start = popover.range(of: "MenuBarPopoverSnapshot.project(")?.lowerBound else {
            throw SourceSliceError.missing("MenuBarPopoverSnapshot.project call")
        }
        guard let open = popover[start...].firstIndex(of: "(") else {
            throw SourceSliceError.missing("project opening paren")
        }
        return try balancedSlice(from: open, in: popover, label: "project")
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

    private func index(of needle: String, in haystack: String) throws -> Int {
        guard let range = haystack.range(of: needle) else {
            throw SourceSliceError.missing(needle)
        }
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum SourceSliceError: Error {
    case missing(String)
}
