import XCTest
@testable import SamplingCore

/// Settings control for Pulse's own login item. Does not call SMAppService.
final class LoginItemWiringSourceTests: XCTestCase {
    func testSettingsToggleReadsMainAppStatusAndRegistersOnlyPulse() throws {
        let view = try WiringSourceText.text(for: "PulseSettingsView")
        XCTAssertTrue(view.contains("Section(\"登录时打开 Pulse\")"))
        XCTAssertTrue(view.contains("Toggle(\"登录时打开 Pulse\""))
        XCTAssertTrue(view.contains("LoginItemProjection.control"))
        XCTAssertTrue(view.contains("SMAppService.mainApp.status"))
        XCTAssertTrue(view.contains("SMAppService.mainApp.register()"))
        XCTAssertTrue(view.contains("SMAppService.mainApp.unregister()"))
        XCTAssertTrue(view.contains("SMAppService.openSystemSettingsLoginItems()"))
        XCTAssertTrue(view.contains("LoginItemProjection.openSettingsButton"))
        XCTAssertTrue(view.contains(".requiresApproval"))
        XCTAssertTrue(view.contains("registrationError"))
        XCTAssertTrue(view.contains("NSApplication.didBecomeActiveNotification"))
        XCTAssertEqual(occurrenceCount(of: "@AppStorage", in: view), 1)
        XCTAssertFalse(view.contains("UserDefaults"))
        XCTAssertFalse(view.contains("pulse.login"))
        XCTAssertFalse(view.contains("loginItem("))
        XCTAssertFalse(view.contains("SMLoginItemSetEnabled"))
        XCTAssertFalse(view.contains("登录项清理"))
        XCTAssertFalse(view.contains("UNUserNotification"))

        let model = try repoText("Pulse/Models/LoginItem.swift")
        XCTAssertFalse(model.contains("import ServiceManagement"))
        XCTAssertFalse(model.contains("import SwiftUI"))
        XCTAssertFalse(model.contains("import AppKit"))
        XCTAssertFalse(model.contains("SMAppService"))
        XCTAssertTrue(model.contains("static func control(status:"))

        let untouched = [
            "Pulse/PulseApp.swift",
            "Pulse/MenuBar/PulseAppDelegate.swift",
            "Pulse/ViewModels/MemoryDashboardVM.swift",
            "Pulse/ViewModels/MemoryDashboardVM+QuitSession.swift",
            "Pulse/ViewModels/MemoryDashboardVM+TopAppLocation.swift",
            "Pulse/Views/MemoryDashboardView.swift",
            "Pulse/Views/SharedUI.swift",
            "Pulse/MenuBar/MainWindowAnchor.swift",
        ]
        for path in untouched {
            let source = try repoText(path)
            XCTAssertFalse(source.contains("SMAppService"), path)
            XCTAssertFalse(source.contains("LoginItem"), path)
        }
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
        haystack.components(separatedBy: needle).count - 1
    }
}
