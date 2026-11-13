import XCTest
@testable import SamplingCore

/// Settings window and optional menu-bar reading. Linux SamplingCore does not compile the app.
/// These tests read source text. They do not open a window or touch the menu bar.
final class MenuBarReadingWiringSourceTests: XCTestCase {
    func testSettingsSceneSuppliesCommandCommaWithoutStoringAPreferenceInTheApp() throws {
        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertTrue(app.contains("Settings {"))
        XCTAssertTrue(app.contains("PulseSettingsView()"))
        XCTAssertFalse(app.contains("keyboardShortcut(\",\""))
        XCTAssertFalse(app.contains("UserDefaults"))
        XCTAssertFalse(app.contains("AppStorage"))
        XCTAssertFalse(app.contains("SceneStorage"))
    }

    func testSettingsPageKeepsTheMenuBarSection() throws {
        let view = try repoText("Pulse/Views/PulseSettingsView.swift")
        XCTAssertEqual(occurrenceCount(of: "Form {", in: view), 1)
        XCTAssertEqual(occurrenceCount(of: "Section(\"", in: view), 3)
        XCTAssertTrue(view.contains("Section(\"菜单栏\")"))
        XCTAssertTrue(view.contains("Section(\"告警规则\")"))
        XCTAssertFalse(view.contains("Section(\"通知\")"))
        XCTAssertTrue(view.contains("Picker("))
        XCTAssertTrue(view.contains("MenuBarReadingMode.allCases"))
        XCTAssertTrue(view.contains("@AppStorage(MenuBarReadingPreference.defaultsKey)"))
        XCTAssertTrue(view.contains(".pickerStyle(.radioGroup)"))
        XCTAssertFalse(view.contains("UNUserNotification"))
    }

    func testPreferenceStorageStaysOutOfTheForbiddenFiles() throws {
        let model = try repoText("Pulse/Models/MenuBarReading.swift")
        XCTAssertTrue(model.contains("UserDefaults"))
        XCTAssertTrue(model.contains("static let defaultsKey"))
        XCTAssertFalse(model.contains("import AppKit"))
        XCTAssertFalse(model.contains("import SwiftUI"))

        let forbidden = [
            "Pulse/PulseApp.swift",
            "Pulse/ViewModels/MemoryDashboardVM.swift",
            "Pulse/ViewModels/MemoryDashboardVM+QuitSession.swift",
            "Pulse/ViewModels/MemoryDashboardVM+TopAppLocation.swift",
            "Pulse/Views/MemoryDashboardView.swift",
            "Pulse/Views/SharedUI.swift",
            "Pulse/MenuBar/MainWindowAnchor.swift",
        ]
        for path in forbidden {
            let source = try repoText(path)
            XCTAssertFalse(source.contains("UserDefaults"), path)
            XCTAssertFalse(source.contains("AppStorage"), path)
            XCTAssertFalse(source.contains("SceneStorage"), path)
        }
    }

    func testMenuBarDotResolveKeepsAnEmptyTitle() throws {
        let model = try repoText("Pulse/MenuBar/MenuBarStatus.swift")
        let dot = try slice(from: "static func resolve(pressure:", until: "enum MenuBarStatusItemAction", in: model)
        XCTAssertEqual(occurrenceCount(of: "statusItemTitle: \"\"", in: dot), 2)
        XCTAssertFalse(dot.contains("MenuBarReading"))
        XCTAssertFalse(dot.contains("ByteFormat"))
        XCTAssertFalse(dot.contains("CPUPercentText"))
    }

    func testControllerRefreshesTheReadingWithoutReplacingTheDot() throws {
        let controller = try repoText("Pulse/MenuBar/MenuBarController.swift")
        XCTAssertTrue(controller.contains("MenuBarReadingTitle.string"))
        XCTAssertTrue(controller.contains("MenuBarReadingPreference.mode()"))
        XCTAssertTrue(controller.contains("MenuBarStatusItemLayout.resolve"))
        XCTAssertTrue(controller.contains("NSStatusItem.squareLength"))
        XCTAssertTrue(controller.contains("NSStatusItem.variableLength"))
        XCTAssertTrue(controller.contains(".imageOnly"))
        XCTAssertTrue(controller.contains(".imageLeading"))
        XCTAssertTrue(controller.contains("NSFont.monospacedDigitSystemFont"))
        XCTAssertTrue(controller.contains("UserDefaults.didChangeNotification"))
        XCTAssertTrue(controller.contains("samplingFailed"))
        XCTAssertTrue(controller.contains("showSettingsWindow"))
        XCTAssertFalse(controller.contains("button.title = dot.statusItemTitle"))

        let render = try functionBody(named: "render", in: controller)
        let titleAt = try index(of: "MenuBarReadingTitle.string", in: render)
        let guardAt = try index(of: "guard dot != rendered", in: render)
        XCTAssertLessThan(titleAt, guardAt)

        let dotCase = try slice(from: "case .dot:", until: "case .reading:", in: controller)
        XCTAssertTrue(dotCase.contains("NSStatusItem.squareLength"))
        XCTAssertTrue(dotCase.contains(".imageOnly"))
        XCTAssertFalse(dotCase.contains("variableLength"))
        let readingCase = try slice(from: "case .reading:", until: "button.toolTip", in: controller)
        XCTAssertTrue(readingCase.contains("NSStatusItem.variableLength"))
        XCTAssertTrue(readingCase.contains(".imageLeading"))
        XCTAssertTrue(readingCase.contains("NSFont.monospacedDigitSystemFont"))
        XCTAssertFalse(readingCase.contains("squareLength"))
    }

    func testPopoverSettingsButtonStaysInTheOpenPulseSlot() throws {
        let view = try repoText("Pulse/MenuBar/MenuBarPopoverView.swift")
        XCTAssertTrue(view.contains(".frame(width: 248, alignment: .topLeading)"))
        XCTAssertFalse(view.contains("filter"))
        XCTAssertFalse(view.contains("visibleRows"))
        XCTAssertFalse(view.contains("risingOnlyFilter"))
        XCTAssertTrue(view.contains("MenuBarCopy.openPulseTitle"))
        XCTAssertTrue(view.contains("MenuBarReadingCopy.openSettingsTitle"))
        XCTAssertEqual(MenuBarReadingCopy.openSettingsTitle, "设置")

        let host = try slice(from: "case .hostPressure:", until: "case .topProcesses:", in: view)
        XCTAssertFalse(host.contains("Button"))
        let open = try slice(from: "case .openPulse:", until: "private var topProcessesSlot", in: view)
        XCTAssertTrue(open.contains("onOpenPulse"))
        XCTAssertTrue(open.contains("onOpenSettings"))
        XCTAssertEqual(MenuBarPopoverShell.sections.count, 3)
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
        let patterns = ["func \(name)(", "func \(name)()", "private func \(name)("]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw SourceSliceError.missing(name)
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

    private func slice(from start: String, until end: String, in source: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
        else { throw SourceSliceError.missing(start) }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
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
