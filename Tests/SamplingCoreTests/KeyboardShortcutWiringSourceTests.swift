import XCTest
@testable import SamplingCore

/// Phase 25 scene-command and main-window frame wiring.
///
/// Linux SamplingCore does not compile `PulseApp`, `Views`, or `MainWindowAnchor`.
/// These tests read source text. They do not press keys, move focus, quit a
/// process, or relaunch the window.
final class KeyboardShortcutWiringSourceTests: XCTestCase {
    /// ⌘1 memory, ⌘2 CPU, ⌘3 disk, ⌘4 network, ⌘5 machine. GPU is not selectable and has no shortcut.
    /// Digit order follows `ResourceTab.allCases`, not the user-story phrase that lists network before disk.
    func testCommandDigitsFollowSelectableResourceTabOrder() throws {
        let shared = try WiringSourceText.text(for: "SharedUI")
        let memory = try index(of: "case memory", in: shared)
        let cpu = try index(of: "case cpu", in: shared)
        let disk = try index(of: "case disk", in: shared)
        let network = try index(of: "case network", in: shared)
        let machine = try index(of: "case machine", in: shared)
        let gpu = try index(of: "case gpu", in: shared)
        XCTAssertLessThan(memory, cpu)
        XCTAssertLessThan(cpu, disk)
        XCTAssertLessThan(disk, network)
        XCTAssertLessThan(network, machine)
        XCTAssertLessThan(machine, gpu)

        let tabs = try braceBody(after: "struct ResourceTabs", in: shared)
        XCTAssertTrue(tabs.contains("allCases.filter(\\.isEnabled)"))
        XCTAssertFalse(tabs.contains("disabledTab"))
        XCTAssertFalse(shared.contains("keyboardShortcut"))

        let app = try repoText("Pulse/PulseApp.swift")
        let memoryToCPU = try between("selectPage(.memory)", "selectPage(.cpu)", in: app)
        let cpuToDisk = try between("selectPage(.cpu)", "selectPage(.disk)", in: app)
        let diskToNetwork = try between("selectPage(.disk)", "selectPage(.network)", in: app)
        XCTAssertTrue(memoryToCPU.contains(shortcut("1")))
        XCTAssertFalse(memoryToCPU.contains(shortcut("2")))
        XCTAssertTrue(cpuToDisk.contains(shortcut("2")))
        XCTAssertFalse(cpuToDisk.contains(shortcut("3")))
        XCTAssertTrue(diskToNetwork.contains(shortcut("3")))
        XCTAssertFalse(diskToNetwork.contains(shortcut("4")))
        let networkToMachine = try between("selectPage(.network)", "selectPage(.machine)", in: app)
        XCTAssertTrue(networkToMachine.contains(shortcut("4")))
        XCTAssertFalse(networkToMachine.contains(shortcut("5")))
        let machineAt = try index(of: "selectPage(.machine)", in: app)
        let fiveAt = try index(of: shortcut("5"), in: app)
        XCTAssertLessThan(machineAt, fiveAt)
        XCTAssertFalse(app[fiveAt...].contains("selectPage("))
        XCTAssertFalse(app.contains("selectPage(.gpu)"))
        XCTAssertFalse(app.contains("\"GPU\""))

        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        let selectPage = try functionBody(named: "selectPage", in: vm)
        XCTAssertTrue(selectPage.contains("next.select(page)"))
        XCTAssertFalse(app.contains("MenuBarNavigation"))
        XCTAssertFalse(vm.contains("keyboardShortcut"))

        let dashboard = try WiringSourceText.text(for: "MemoryDashboardView")
        XCTAssertFalse(dashboard.contains("keyboardShortcut"))
    }

    func testMenuBarDoesNotSelectPagesOrInstallKeyboardShortcuts() throws {
        let menuBar = try repoText("Pulse/MenuBar/MenuBarController.swift")
        let popover = try repoText("Pulse/MenuBar/MenuBarPopoverView.swift")
        XCTAssertFalse(menuBar.contains("keyboardShortcut"))
        XCTAssertFalse(menuBar.contains("selectPage"))
        XCTAssertFalse(popover.contains("keyboardShortcut"))
        XCTAssertFalse(popover.contains("selectPage"))
    }

    func testAppMenuClearsNewItemAndQuitsWithCommandQ() throws {
        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertTrue(app.contains("CommandGroup(replacing: .newItem) {}"))
        XCTAssertTrue(app.contains(".keyboardShortcut(\"q\")"))
        XCTAssertTrue(app.contains("MenuBarCopy.quitTitle"))
        XCTAssertTrue(app.contains("NSApp.terminate(nil)"))
    }

    func testCommandFFocusesTheNameFilterThroughSceneFocusState() throws {
        let shared = try WiringSourceText.text(for: "SharedUI")
        let field = try braceBody(after: "struct AppFilterField", in: shared)
        XCTAssertEqual(occurrenceCount(of: "@FocusState", in: shared), 1)
        XCTAssertTrue(field.contains("@FocusState private var isFocused: Bool"))
        XCTAssertTrue(field.contains(".focused($isFocused)"))
        XCTAssertTrue(field.contains(".focusedSceneValue(\\.focusNameFilter)"))
        XCTAssertTrue(field.contains("isFocused = true"))
        XCTAssertTrue(field.contains(".focusedSceneValue(\\.nameFilterFocused, isFocused)"))
        XCTAssertFalse(field.contains("keyboardShortcut"))
        XCTAssertFalse(field.contains("UserDefaults"))
        XCTAssertFalse(field.contains("AppStorage"))
        XCTAssertFalse(field.contains("SceneStorage"))
        XCTAssertEqual(occurrenceCount(of: "text = \"\"", in: field), 1)

        let dashboard = try WiringSourceText.text(for: "MemoryDashboardView")
        XCTAssertTrue(dashboard.contains("AppFilterField(text: $vm.filter)"))
        XCTAssertFalse(dashboard.contains("@FocusState"))
        XCTAssertFalse(dashboard.contains("focusedSceneValue"))
        XCTAssertFalse(dashboard.contains("UserDefaults"))
        XCTAssertFalse(dashboard.contains("AppStorage"))
        XCTAssertFalse(dashboard.contains("SceneStorage"))

        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertTrue(app.contains("@FocusedValue(\\.focusNameFilter)"))
        XCTAssertTrue(app.contains("focusNameFilter?()"))
        XCTAssertTrue(app.contains(shortcut("f")))
        XCTAssertTrue(app.contains(".disabled(focusNameFilter == nil)"))
        XCTAssertFalse(app.contains("dashboard.focus"))
        XCTAssertFalse(app.contains("UserDefaults"))
        XCTAssertFalse(app.contains("AppStorage"))
        XCTAssertFalse(app.contains("SceneStorage"))

        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        XCTAssertFalse(vm.contains("focusNameFilter"))
        XCTAssertFalse(vm.contains("nameFilterFocused"))
        XCTAssertTrue(vm.contains("func focusMemoryPage()"))
    }

    func testCommandDeleteCallsQuitSelectedAndIsOmittedWhileTheFilterIsFocused() throws {
        let app = try repoText("Pulse/PulseApp.swift")
        let command = try functionBody(named: "ordinaryQuitCommand", in: app)
        XCTAssertTrue(command.contains("if nameFilterFocused == true"))
        let focusedBranch = try braceBody(after: "if nameFilterFocused == true", in: command)
        XCTAssertFalse(focusedBranch.contains("keyboardShortcut"))
        XCTAssertFalse(focusedBranch.contains(".disabled"))
        XCTAssertFalse(focusedBranch.contains("Button("))
        XCTAssertFalse(focusedBranch.contains("dashboard.quitSelected()"))
        let elseBranch = try braceBody(after: "} else", in: command)
        XCTAssertTrue(elseBranch.contains(".keyboardShortcut(.delete, modifiers: .command)"))
        XCTAssertFalse(elseBranch.contains("Button("))
        XCTAssertFalse(elseBranch.contains("dashboard.quitSelected()"))
        XCTAssertEqual(occurrenceCount(of: "Button(\"退出选中进程\")", in: app), 1)
        let buttonAction = try braceBody(after: "Button(\"退出选中进程\")", in: app)
        XCTAssertTrue(buttonAction.contains("Task { await dashboard.quitSelected() }"))
        XCTAssertFalse(buttonAction.contains("keyboardShortcut"))
        XCTAssertEqual(occurrenceCount(of: "Task { await dashboard.quitSelected() }", in: app), 1)
        XCTAssertEqual(occurrenceCount(of: "keyboardShortcut(.delete", in: app), 1)
        XCTAssertFalse(command.contains("forceQuitSelected"))
        XCTAssertFalse(app.contains("forceQuitSelected"))
        XCTAssertFalse(app.contains("ProcessQuitSession"))
        XCTAssertFalse(app.contains(".disabled(nameFilterFocused"))

        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        let quit = try functionBody(named: "quitSelected", in: vm)
        XCTAssertTrue(quit.contains("ProcessQuitSession.ordinaryTerminate"))
        XCTAssertTrue(vm.contains("func forceQuitSelected("))
        XCTAssertFalse(vm.contains("keyboardShortcut"))

        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebarQuitControls")
        XCTAssertTrue(sidebar.contains("await vm.quitSelected()"))
        XCTAssertTrue(sidebar.contains("await vm.forceQuitSelected()"))
        XCTAssertFalse(sidebar.contains("keyboardShortcut"))
    }

    func testMainWindowAutosavesFrameWithoutStoringTabSortOrFilter() throws {
        let anchor = try repoText("Pulse/MenuBar/MainWindowAnchor.swift")
        let attach = try functionBody(named: "attach", in: anchor)
        XCTAssertTrue(attach.contains("setFrameAutosaveName(PulseWindowID.main)"))
        XCTAssertFalse(anchor.contains("UserDefaults"))
        XCTAssertFalse(anchor.contains("AppStorage"))
        XCTAssertFalse(anchor.contains("SceneStorage"))
        XCTAssertFalse(anchor.contains("restorationBehavior"))
        XCTAssertFalse(anchor.contains("selectedPage"))
        XCTAssertFalse(anchor.contains("filter"))
        XCTAssertFalse(attach.contains("sort"))

        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertFalse(app.contains("UserDefaults"))
        XCTAssertFalse(app.contains("AppStorage"))
        XCTAssertFalse(app.contains("SceneStorage"))
        XCTAssertFalse(app.contains("restorationBehavior"))
        XCTAssertFalse(app.contains("selectedPage ="))

        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        XCTAssertTrue(vm.contains("@Published private(set) var navigation = DashboardNavigation()"))
        XCTAssertFalse(vm.contains("UserDefaults"))
        XCTAssertFalse(vm.contains("AppStorage"))
        XCTAssertFalse(vm.contains("SceneStorage"))

        let dashboard = try WiringSourceText.text(for: "MemoryDashboardView")
        XCTAssertFalse(dashboard.contains("UserDefaults"))
        XCTAssertFalse(dashboard.contains("AppStorage"))
        XCTAssertFalse(dashboard.contains("SceneStorage"))

        let shared = try WiringSourceText.text(for: "SharedUI")
        XCTAssertFalse(shared.contains("UserDefaults"))
        XCTAssertFalse(shared.contains("AppStorage"))
        XCTAssertFalse(shared.contains("SceneStorage"))
    }

    private func shortcut(_ key: String) -> String {
        ".keyboardShortcut(\"\(key)\", modifiers: .command)"
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

    private func between(_ start: String, _ end: String, in source: String) throws -> String {
        let startIndex = try index(of: start, in: source)
        let endIndex = try index(of: end, in: source)
        guard startIndex < endIndex else { throw SourceSliceError.missing("\(start) before \(end)") }
        return String(source[startIndex..<endIndex])
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["func \(name)(", "func \(name)()", "private func \(name)(", "var \(name):"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw SourceSliceError.missing(name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound,
              let brace = source[start...].firstIndex(of: "{")
        else { throw SourceSliceError.missing(needle) }
        return try balancedSlice(from: brace, in: source, label: needle)
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw SourceSliceError.missing(needle)
        }
        return found
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        var depth = 0
        var index = start
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...index]) }
            }
            index = source.index(after: index)
        }
        throw SourceSliceError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum SourceSliceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
