import XCTest
@testable import SamplingCore

/// Settings switch and notification delivery stay out of the view model.
/// Linux reads source text. It does not post a notification or open a window.
final class PressureNoticeWiringSourceTests: XCTestCase {
    func testSettingsSectionDefaultsOnAndShowsDeniedPermission() throws {
        let view = try repoText("Pulse/Views/PulseSettingsView.swift")
        XCTAssertTrue(view.contains("Section(\"通知\")"))
        XCTAssertTrue(view.contains(
            "@AppStorage(PressureNoticePreference.defaultsKey) private var pressureNoticeEnabled = true"
        ))
        XCTAssertTrue(view.contains("Toggle(\"压力偏高时通知\", isOn: $pressureNoticeEnabled)"))
        XCTAssertTrue(view.contains("Text(PressureNoticeCopy.permissionDenied)"))
        XCTAssertTrue(view.contains("PressureNoticeCenter.requestPermission"))
        XCTAssertFalse(view.contains("UNUserNotification"))
        XCTAssertFalse(view.contains("NSAlert"))
    }

    func testCenterFeedsNilOnFailureAndPostsOnlyAfterASendDecision() throws {
        let center = try repoText("Pulse/MenuBar/PressureNoticeCenter.swift")
        XCTAssertTrue(center.contains("UNUserNotificationCenter"))
        XCTAssertTrue(center.contains("requestAuthorization"))
        XCTAssertFalse(center.contains("NSAlert"))
        XCTAssertTrue(center.contains("TopConsumer.leading"))
        XCTAssertTrue(center.contains("identifier == Self.requestIdentifier"))
        XCTAssertTrue(center.contains("openMemoryPage()"))

        let ingest = try functionBody(named: "ingest", in: center)
        let reading = try index(of: "PressureNoticeReading.pressure", in: ingest)
        let advance = try index(of: "PressureNotice.advance", in: ingest)
        let send = try index(of: "guard decision.send else { return }", in: ingest)
        let post = try index(of: "post(", in: ingest)
        XCTAssertLessThan(reading, advance)
        XCTAssertLessThan(advance, send)
        XCTAssertLessThan(send, post)
        XCTAssertTrue(ingest.contains("samplingFailed: dashboard.samplingFailed"))
        XCTAssertTrue(ingest.contains("enabled: PressureNoticePreference.isEnabled()"))
        XCTAssertTrue(ingest.contains("PressureNoticeCopy.body"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertFalse(vm.contains("PressureNotice"))
        XCTAssertFalse(vm.contains("UNUserNotification"))
        XCTAssertFalse(vm.contains("UserDefaults"))
    }

    func testClickUsesTheSamePathAsOpenPulse() throws {
        let delegate = try repoText("Pulse/MenuBar/PulseAppDelegate.swift")
        let launch = try functionBody(named: "didLaunch", in: delegate)
        XCTAssertTrue(launch.contains("installPressureNotices()"))
        let install = try functionBody(named: "installPressureNotices", in: delegate)
        XCTAssertTrue(install.contains("pressureNotices.install"))
        XCTAssertTrue(install.contains("self?.focusMemoryPage()"))
        let bind = try functionBody(named: "bind", in: delegate)
        XCTAssertTrue(bind.contains("pressureNotices.observe(dashboard)"))
        XCTAssertFalse(delegate.contains("UserDefaults"))
        XCTAssertFalse(delegate.contains("AppStorage"))
    }

    func testPortableMachineIsRegisteredAndTheCenterIsExcluded() throws {
        let package = try repoText("Package.swift")
        let excluded = try slice(from: "exclude: [", until: "sources: [", in: package)
        XCTAssertTrue(excluded.contains("\"MenuBar/PressureNoticeCenter.swift\""))
        let sources = try slice(from: "sources: [", until: ".testTarget(", in: package)
        XCTAssertTrue(sources.contains("\"Models/PressureNotice.swift\""))
        XCTAssertFalse(sources.contains("PressureNoticeCenter"))

        let model = try repoText("Pulse/Models/PressureNotice.swift")
        XCTAssertFalse(model.contains("import AppKit"))
        XCTAssertFalse(model.contains("import SwiftUI"))
        XCTAssertFalse(model.contains("import UserNotifications"))
        XCTAssertFalse(model.contains("UNUserNotificationCenter"))
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
        let patterns = ["func \(name)(", "func \(name)()", "private func \(name)(", "private func \(name)()"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw PressureNoticeSourceError.missing(name)
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw PressureNoticeSourceError.missing(needle)
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
        throw PressureNoticeSourceError.missing("balanced brace for \(label)")
    }

    private func slice(from start: String, until end: String, in source: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
        else { throw PressureNoticeSourceError.missing(start) }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}

private enum PressureNoticeSourceError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
