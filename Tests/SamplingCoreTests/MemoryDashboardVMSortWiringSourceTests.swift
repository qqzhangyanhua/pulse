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

    func testVMSourceHoldsOneUnpublishedPublication() throws {
        let source = try vmSource()
        let needle = "var publication = MemoryPageSortPublication()"
        let count = source.components(separatedBy: needle).count - 1
        XCTAssertEqual(
            count,
            1,
            "VM MainActor holds one MemoryPageSortPublication; this is a source check, not a VM run"
        )
        XCTAssertFalse(source.contains("@Published lastMemorySort"))
        XCTAssertFalse(source.contains("lastMemorySort"))
        for line in source.components(separatedBy: .newlines) where line.contains("MemoryPageSortPublication") {
            XCTAssertFalse(
                line.contains("@Published"),
                "publication is not a second @Published sort state machine: \(line)"
            )
        }
    }

    func testMenuBarPopoverProjectsPublicationSortNotLiveTableSort() throws {
        let source = try vmSource()
        let popover = try functionBody(named: "menuBarPopover", in: source)
        let call = try projectCall(in: popover)

        XCTAssertTrue(
            call.contains("sort: publication.sort"),
            "menuBarPopover must sync project(sort: publication.sort)"
        )
        XCTAssertTrue(call.contains("rows: rows"))
        XCTAssertFalse(call.contains("visibleRows"))
        XCTAssertFalse(call.contains("tableSort"))
        XCTAssertFalse(call.contains("navigation.sort"))
        XCTAssertFalse(call.contains("filter"))
        XCTAssertFalse(call.contains("risingOnly"))
        XCTAssertFalse(popover.contains("await sampler"))
        XCTAssertFalse(
            source.contains("never the filtered table or its header sort"),
            "stale 'never header sort' comment must not remain on menuBarPopover"
        )
        XCTAssertTrue(
            source.contains("published memory-page sort"),
            "comment should name the publication, not claim header sort is ignored"
        )
    }

    func testPublishMemoryPageSortWritesPublicationBeforeTheSameSamplerSort() throws {
        let source = try vmSource()
        let body = try functionBody(named: "publishMemoryPageSort", in: source)

        XCTAssertTrue(
            body.contains("publication.publishMemoryPageSort"),
            "must use the Darwin-free publish handoff"
        )
        let publishIndex = try index(of: "publication.publishMemoryPageSort", in: body)
        let taskIndex = try index(of: "Task { await sampler.setMemoryPageSort(sort) }", in: body)
        XCTAssertLessThan(publishIndex, taskIndex, "publication writes first; Sampler is not awaited for UI")
        XCTAssertTrue(body.contains("await sampler.setMemoryPageSort(sort)"))
        XCTAssertFalse(body.contains("setMemoryPageSort(tableSort)"))
        XCTAssertFalse(body.contains("setMemoryPageSort(publication.sort)"))
        XCTAssertFalse(
            body.contains("await sampler.setMemoryPageSort")
                && body.contains("menuBarPopover"),
            "do not await Actor to refresh the popover"
        )
    }

    func testCallSitesShareTheSamePublishEntry() throws {
        let source = try vmSource()
        for name in ["focusMemoryPage", "selectPage", "setTableSort", "start"] {
            let body = try functionBody(named: name, in: source)
            XCTAssertTrue(
                body.contains("publishMemoryPageSort()"),
                "\(name) must go through the same publish entry (source check, not a VM run)"
            )
        }
    }

    private func vmSource() throws -> String {
        try String(contentsOf: repoFile("Pulse/ViewModels/MemoryDashboardVM.swift"), encoding: .utf8)
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
}

private enum SourceSliceError: Error {
    case missing(String)
}
