import XCTest
@testable import SamplingCore

/// Settings switch and notification delivery stay out of the view model.
/// Linux reads source text. It does not post a notification or open a window.
final class PressureNoticeWiringSourceTests: XCTestCase {
    func testSettingsSectionDefaultsOnAndShowsDeniedPermission() throws {
        let view = try repoText("Pulse/Views/PulseSettingsView.swift")
        XCTAssertTrue(view.contains("Section(\"告警规则\")"))
        XCTAssertFalse(view.contains("Section(\"通知\")"))
        XCTAssertTrue(view.contains(
            "@AppStorage(PressureNoticePreference.defaultsKey) private var pressureNoticeEnabled = true"
        ))
        XCTAssertTrue(view.contains("@AppStorage(AlertRuleStore.defaultsKey)"))
        XCTAssertTrue(view.contains("Toggle(\"压力偏高时通知\", isOn: $pressureNoticeEnabled)"))
        XCTAssertTrue(view.contains("Text(AlertRuleCopy.builtinNote)"))
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
        let advance = try index(of: "AlertRule.memoryPressure.advance", in: ingest)
        let send = try index(of: "if decision.send", in: ingest)
        let post = try index(of: "post(", in: ingest)
        let acceptedGate = try index(of: "guard accepted, let capturedAt", in: ingest)
        let custom = try index(of: "postCustomRules", in: ingest)
        XCTAssertLessThan(reading, advance)
        XCTAssertLessThan(advance, send)
        XCTAssertLessThan(send, post)
        XCTAssertLessThan(post, acceptedGate)
        XCTAssertLessThan(acceptedGate, custom)
        XCTAssertTrue(ingest.contains("samplingFailed: dashboard.samplingFailed"))
        XCTAssertTrue(ingest.contains("enabled: PressureNoticePreference.isEnabled()"))
        XCTAssertTrue(ingest.contains("PressureNoticeCopy.body"))
        XCTAssertTrue(center.contains("AlertRuleEngine"))
        XCTAssertTrue(center.contains("dashboard.systemCpuPercent"))
        XCTAssertTrue(center.contains("dashboard.machinePageCelsius"))
        XCTAssertTrue(center.contains("machineFacts?.volume.availableBytes"))
        XCTAssertFalse(center.contains("chipTemperature"))
        XCTAssertFalse(center.contains("ChipTemperature"))
        let chip = try repoText("Pulse/ViewModels/MemoryDashboardVM+ChipTemperature.swift")
        XCTAssertTrue(chip.contains("selectedPage == .machine"))
        XCTAssertTrue(chip.contains("chipTemperature.visitSucceeded"))
        XCTAssertTrue(chip.contains("celsius.isFinite"))
        XCTAssertTrue(center.contains("AlertNoticeRoute.pageKey"))
        XCTAssertTrue(center.contains("AlertNoticeRoute.pidKey"))
        XCTAssertTrue(center.contains("AlertNoticeRoute.decode"))
        XCTAssertFalse(center.contains("busiestCorePercent"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertFalse(vm.contains("PressureNotice"))
        XCTAssertFalse(vm.contains("AlertRule"))
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
        XCTAssertTrue(install.contains("self?.openCustomAlert"))
        XCTAssertFalse(install.contains("activateMainWindow"))
        XCTAssertFalse(install.contains("select(pid:"))
        let opened = try functionBody(named: "openCustomAlert", in: delegate)
        let page = try index(of: "selectPage", in: opened)
        let pid = try index(of: "select(pid:", in: opened)
        let activate = try index(of: "activateMainWindow()", in: opened)
        XCTAssertLessThan(page, pid)
        XCTAssertLessThan(pid, activate)
        let bind = try functionBody(named: "bind", in: delegate)
        XCTAssertTrue(bind.contains("startSampling()"))
        let sampling = try functionBody(named: "startSampling", in: delegate)
        XCTAssertTrue(sampling.contains("pressureNotices.observe(dashboard)"))
        XCTAssertFalse(delegate.contains("UserDefaults"))
        XCTAssertFalse(delegate.contains("AppStorage"))
    }

    /// Launch owns the one dashboard. A window is not the only `start()`.
    func testLaunchStartsTheSameDashboardWithoutWaitingForAWindow() throws {
        let delegate = try repoText("Pulse/MenuBar/PulseAppDelegate.swift")
        let launch = try functionBody(named: "didLaunch", in: delegate)
        XCTAssertTrue(launch.contains("startSampling()"))
        let sampling = try functionBody(named: "startSampling", in: delegate)
        XCTAssertTrue(sampling.contains("dashboard.start()"))
        XCTAssertTrue(sampling.contains("menuBar.observe(dashboard)"))
        XCTAssertTrue(sampling.contains("pressureNotices.observe(dashboard)"))
        XCTAssertTrue(sampling.contains("applyPace()"))
        XCTAssertTrue(delegate.contains("let dashboard = MemoryDashboardVM()"))
        XCTAssertEqual(occurrenceCount(of: "MemoryDashboardVM()", in: delegate), 1)
        XCTAssertFalse(delegate.contains("MemoryDashboardVM?"))
        XCTAssertTrue(delegate.contains("MenuBarSamplingGate(sceneActive: true, mainWindowVisible: false)"))

        let bind = try functionBody(named: "bind", in: delegate)
        XCTAssertTrue(bind.contains("startSampling()"))
        XCTAssertTrue(bind.contains("openMainWindow = openWindow"))
        XCTAssertTrue(bind.contains("dashboard === self.dashboard"))
        XCTAssertFalse(bind.contains("MemoryDashboardVM()"))
        let terminate = try functionBody(named: "applicationShouldTerminateAfterLastWindowClosed", in: delegate)
        XCTAssertTrue(terminate.contains("MenuBarLifecycle.terminateAfterLastWindowClosed"))

        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertFalse(app.contains("MemoryDashboardVM()"))
        XCTAssertTrue(app.contains("environmentObject(appDelegate.dashboard)"))
        XCTAssertTrue(app.contains("PulseWindowCommands(dashboard: appDelegate.dashboard)"))
        let hook = try structBody(named: "OpenWindowHook", in: app)
        XCTAssertTrue(hook.contains("delegate.bind(dashboard)"))
        XCTAssertTrue(hook.contains("openWindow(id: PulseWindowID.main)"))
        let outsideHook = app.replacingOccurrences(of: hook, with: "")
        XCTAssertTrue(outsideHook.contains("bindOpenWindow"))
        XCTAssertTrue(outsideHook.contains("openWindow(id: PulseWindowID.main)"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let start = try functionBody(named: "start", in: vm)
        XCTAssertTrue(start.contains("guard !started else { return }"))
        XCTAssertEqual(occurrenceCount(of: "loopTask = Task", in: vm), 1)
    }

    func testPortableMachineIsRegisteredAndTheCenterIsExcluded() throws {
        let package = try repoText("Package.swift")
        let excluded = try slice(from: "exclude: [", until: "sources: [", in: package)
        XCTAssertTrue(excluded.contains("\"MenuBar/PressureNoticeCenter.swift\""))
        let sources = try slice(from: "sources: [", until: ".testTarget(", in: package)
        XCTAssertTrue(sources.contains("\"Models/AlertRule.swift\""))
        XCTAssertTrue(sources.contains("\"Models/AlertRule+Settings.swift\""))
        XCTAssertFalse(sources.contains("PulseSettingsView+AlertRules"))
        XCTAssertFalse(sources.contains("\"Models/PressureNotice.swift\""))
        XCTAssertFalse(sources.contains("PressureNoticeCenter"))

        let model = try repoText("Pulse/Models/AlertRule.swift")
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

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func structBody(named name: String, in source: String) throws -> String {
        let pattern = "struct \(name)"
        guard let range = source.range(of: pattern),
              let brace = source[range.lowerBound...].firstIndex(of: "{")
        else { throw PressureNoticeSourceError.missing(name) }
        return try balancedSlice(from: brace, in: source, label: name)
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
