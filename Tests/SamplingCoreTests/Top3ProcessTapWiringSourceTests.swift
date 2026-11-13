import XCTest
@testable import SamplingCore

/// Source contract for the Top3 process-row schedule.
/// Reading the controller is not a Mac click and not VoiceOver.
final class Top3ProcessTapWiringSourceTests: XCTestCase {
    func testHandlePopoverTapUsesTheProcessEntryThenActivatesOnce() throws {
        let controller = try repoText("Pulse/MenuBar/MenuBarController.swift")
        let tap = try functionBody(named: "handlePopoverTap", in: controller)
        let process = try slice(from: "case .process", until: "case .openPulse", in: tap)
        XCTAssertLessThan(
            try index(of: "dismiss:", in: process),
            try index(of: "activate:", in: process)
        )
        XCTAssertEqual(occurrenceCount(of: "Top3ProcessTap.perform", in: process), 1)
        XCTAssertEqual(occurrenceCount(of: "onActivateMainWindow()", in: process), 1)
        XCTAssertEqual(occurrenceCount(of: "onOpenPulse()", in: process), 0)
        XCTAssertFalse(process.contains("focusMemoryPage"))

        let open = try slice(from: "case .openPulse", until: "private func openSettings", in: controller)
        XCTAssertEqual(occurrenceCount(of: "MenuBarOpenPulseTap.perform", in: open), 1)
        XCTAssertEqual(occurrenceCount(of: "onOpenPulse()", in: open), 1)
        XCTAssertEqual(occurrenceCount(of: "Top3ProcessTap.perform", in: open), 0)
        XCTAssertEqual(occurrenceCount(of: "onActivateMainWindow()", in: open), 0)

        let entry = try repoText("Pulse/MenuBar/Top3ProcessTap.swift")
        let perform = try functionBody(named: "perform", in: entry)
        XCTAssertEqual(occurrenceCount(of: "host.focusMemoryPage()", in: perform), 1)
        XCTAssertEqual(occurrenceCount(of: "host.selectPidIfPresent(pid)", in: perform), 1)
        XCTAssertLessThan(
            try index(of: "prepare(pid, on: host)", in: perform),
            try index(of: "host.selectPidIfPresent(pid)", in: perform)
        )
        XCTAssertLessThan(
            try index(of: "host.selectPidIfPresent(pid)", in: perform),
            try index(of: "host.focusMemoryPage()", in: perform)
        )
        XCTAssertLessThan(
            try index(of: "host.focusMemoryPage()", in: perform),
            try index(of: "activate()", in: perform)
        )
        XCTAssertEqual(occurrenceCount(of: "onOpenPulse", in: perform), 0)
        XCTAssertTrue(perform.contains("acceptedPid(pid, in: host.rows)"))

        let openPerform = try functionBody(named: "perform", in: entry, after: "enum MenuBarOpenPulseTap")
        XCTAssertEqual(occurrenceCount(of: "openPulse()", in: openPerform), 1)
        XCTAssertFalse(openPerform.contains("Top3ProcessTap"))
        XCTAssertFalse(openPerform.contains("focusMemoryPage"))
        XCTAssertFalse(openPerform.contains("prepare"))
    }

    func testSharedFocusAndActivationStayOnTheirOwnPaths() throws {
        let delegate = try repoText("Pulse/MenuBar/PulseAppDelegate.swift")
        let focus = try functionBody(named: "focusMemoryPage", in: delegate)
        XCTAssertLessThan(
            try index(of: "dashboard.focusMemoryPage()", in: focus),
            try index(of: "NSApp.activate()", in: focus)
        )
        let activate = try functionBody(named: "activateMainWindow", in: delegate)
        XCTAssertFalse(activate.contains("dashboard.focusMemoryPage"))
        XCTAssertTrue(activate.contains("NSApp.activate()"))
        let launch = try functionBody(named: "didLaunch", in: delegate)
        XCTAssertTrue(launch.contains("onOpenPulse: { [weak self] in self?.focusMemoryPage() }"))
        XCTAssertTrue(launch.contains("onActivateMainWindow: { [weak self] in self?.activateMainWindow() }"))
        let reopen = try functionBody(named: "applicationShouldHandleReopen", in: delegate)
        XCTAssertTrue(reopen.contains("self.focusMemoryPage()"))
        XCTAssertFalse(reopen.contains("activateMainWindow"))
        XCTAssertFalse(reopen.contains("Top3ProcessTap"))

        let notices = try repoText("Pulse/MenuBar/PressureNoticeCenter.swift")
        XCTAssertFalse(notices.contains("Top3ProcessTap"))
        let install = try functionBody(named: "installPressureNotices", in: delegate)
        XCTAssertTrue(install.contains("self?.focusMemoryPage()"))
        XCTAssertFalse(install.contains("activateMainWindow"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let vmFocus = try functionBody(named: "focusMemoryPage", in: vm)
        XCTAssertTrue(vmFocus.contains("changePage"))
        XCTAssertTrue(vm.contains("syncMachineWatch()"))
        XCTAssertFalse(vmFocus.contains("Top3ProcessTap"))
        let selection = try repoText("Pulse/Models/DashboardCore+Selection.swift")
        let tail = try functionBody(named: "finishPageChange", in: selection)
        XCTAssertFalse(tail.contains("navigation.focusMemoryPage()"))
        XCTAssertTrue(tail.contains("publishMemoryPageSort()"))
        XCTAssertTrue(tail.contains("applyRisingOnlySelection()"))
        XCTAssertTrue(tail.contains("applyWindowedOnlySelection()"))
        let coreFocus = try functionBody(named: "focusMemoryPage", in: selection)
        XCTAssertTrue(coreFocus.contains("navigation.focusMemoryPage()"))

        let rising = try functionBody(
            named: "selectedPid",
            in: try repoText("Pulse/Models/MemoryGrowthRisingFilter.swift")
        )
        XCTAssertTrue(rising.contains("return hasBadge ? current : nil"))
        let windowed = try functionBody(
            named: "selectedPid",
            in: try repoText("Pulse/Models/WindowedAppFilter.swift")
        )
        XCTAssertTrue(windowed.contains("return pids.contains(current) ? current : nil"))

        let view = try repoText("Pulse/MenuBar/MenuBarPopoverView.swift")
        XCTAssertTrue(view.contains("onSelectProcess(process.pid)"))
        XCTAssertFalse(view.contains("@FocusState"))
        XCTAssertFalse(view.contains("alert"))
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

    private func functionBody(named name: String, in source: String, after marker: String? = nil) throws -> String {
        let patterns = ["func \(name)(", "private func \(name)(", "static func \(name)("]
        var search = source[...]
        if let marker, let range = source.range(of: marker) {
            search = source[range.upperBound...]
        }
        for pattern in patterns {
            guard let range = search.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw TapSourceError.missing(name)
    }

    private func slice(from start: String, until end: String, in source: String) throws -> String {
        guard let lower = source.range(of: start)?.lowerBound,
              let upper = source.range(of: end, range: lower..<source.endIndex)?.lowerBound
        else { throw TapSourceError.missing("\(start) … \(end)") }
        return String(source[lower..<upper])
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw TapSourceError.missing(needle)
        }
        return found
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        var depth = 0
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...cursor]) }
            }
            cursor = source.index(after: cursor)
        }
        throw TapSourceError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum TapSourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
