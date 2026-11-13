import XCTest

/// Phase 26 source constraints. Linux reads text; it does not post thermal
/// notifications or draw the four overviews.
final class ThermalNoticeWiringSourceTests: XCTestCase {
    func testProjectionStaysFreeOfPlatformImports() throws {
        let source = try repoText("Pulse/Models/ThermalNotice.swift")
        XCTAssertTrue(source.contains("static func message(for condition: ThermalCondition) -> String?"))
        for token in ["import Darwin", "import AppKit", "import SwiftUI", "ProcessInfo", "Timer"] {
            XCTAssertFalse(source.contains(token), token)
        }
    }

    func testPackageAndProjectListTheProjection() throws {
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/ThermalNotice.swift\""))
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ThermalNotice.swift in Sources"))
        XCTAssertTrue(project.contains("path = ThermalNotice.swift;"))
    }

    func testThermalAdviceStaysFreeOfPlatformImports() throws {
        let source = try repoText("Pulse/Models/ThermalAdvice.swift")
        XCTAssertTrue(source.contains("static func project(_ processes: [ThermalAdviceCandidate], excludingPid pulsePid: Int32) -> ThermalAdvice"))
        for token in ["import Darwin", "import AppKit", "import SwiftUI", "import Foundation"] {
            XCTAssertFalse(source.contains(token), token)
        }
    }

    func testPackageAndProjectListThermalAdvice() throws {
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/ThermalAdvice.swift\""))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ThermalAdvice.swift in Sources"))
        XCTAssertTrue(project.contains("path = ThermalAdvice.swift;"))
    }

    func testThermalWatchStaysOutOfTheSamplerAndUsesNoTimer() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        for token in ["thermalState", "ThermalNotice", "thermalNotice", "Timer", "ProcessInfo"] {
            XCTAssertFalse(sampler.contains(token), token)
        }
        XCTAssertTrue(vm.contains("ProcessInfo.thermalStateDidChangeNotification"))
        let thermal = try repoText("Pulse/Models/DashboardCore+Thermal.swift")
        XCTAssertTrue(thermal.contains("ThermalNotice.message(for:"))
        XCTAssertFalse(vm.contains("ThermalNotice.message(for:"))
        XCTAssertFalse(vm.contains("Timer"))
        XCTAssertEqual(occurrenceCount(of: "addObserver", in: vm), 1)
    }

    func testMenuBarDoesNotReadThermalState() throws {
        let directory = repoRoot().appendingPathComponent("Pulse/MenuBar", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let sources = files.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(sources.isEmpty)
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in ["thermalNotice", "ThermalNotice", "ThermalCondition", "thermalState"] {
                XCTAssertFalse(text.contains(token), "\(file.lastPathComponent) \(token)")
            }
        }
    }

    func testThermalAdvicePublishesFromSamplesAndClearsWhenTheNoticeEnds() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("ThermalAdvice"))

        let menuBar = repoRoot().appendingPathComponent("Pulse/MenuBar", isDirectory: true)
        let menuSources = try FileManager.default.contentsOfDirectory(at: menuBar, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(menuSources.isEmpty)
        for file in menuSources {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("ThermalAdvice"), file.lastPathComponent)
        }

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"ViewModels\",\n                \"ViewModels/MemoryDashboardVM+ThermalAdvice.swift\","))
        let sourcesList = package.components(separatedBy: "sources:")
        XCTAssertEqual(sourcesList.count, 2)
        XCTAssertFalse(sourcesList[1].contains("MemoryDashboardVM+ThermalAdvice.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("MemoryDashboardVM+ThermalAdvice.swift in Sources"))
        XCTAssertTrue(project.contains("path = \"MemoryDashboardVM+ThermalAdvice.swift\";"))

        let dashboard = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(dashboard.contains("var thermalAdvice: ThermalAdvice? { core.thermalAdvice }"))
        XCTAssertTrue(dashboard.contains("var thermalAdviceLastUpdate: Double?"))
        XCTAssertFalse(dashboard.contains("private var thermalAdviceLastUpdate"))
        XCTAssertFalse(dashboard.contains("@Published var thermalAdviceLastUpdate"))

        let watch = try repoText("Pulse/ViewModels/MemoryDashboardVM+HostWatch.swift")
        XCTAssertTrue(watch.contains("apply(thermalCondition: ThermalCondition(state))"))
        XCTAssertFalse(watch.contains("thermalAdvice ="))

        let advice = try repoText("Pulse/Models/DashboardCore+Thermal.swift")
        XCTAssertFalse(advice.contains("Timer"))
        XCTAssertFalse(advice.contains("addObserver"))
        XCTAssertFalse(advice.contains("ProcessEnumerator"))
        XCTAssertFalse(advice.contains("ProcessInfo"))
        let cleared = try range(of: "thermalAdvice = nil", in: advice)
        let throttle = try range(of: "ThermalAdviceThrottle.shouldUpdate(", in: advice)
        let projectCall = try range(of: "ThermalAdviceProjection.project(", in: advice)
        let unmeasured = try range(of: "if projected.processes.isEmpty, projected.noHighLoad == false", in: advice)
        let stored = try range(of: "thermalAdviceLastUpdate = now", in: advice)
        XCTAssertLessThan(cleared.lowerBound, throttle.lowerBound)
        XCTAssertLessThan(throttle.lowerBound, projectCall.lowerBound)
        XCTAssertLessThan(projectCall.lowerBound, unmeasured.lowerBound)
        XCTAssertLessThan(unmeasured.lowerBound, stored.lowerBound)
        let hold = try braceBody(after: "if projected.processes.isEmpty, projected.noHighLoad == false", in: advice)
        XCTAssertEqual(compact(hold), "{return}")
        XCTAssertTrue(advice.contains("excludingPid: ownPid"))
        XCTAssertEqual(occurrenceCount(of: "addObserver", in: try WiringSourceText.text(for: "MemoryDashboardVM")), 1)
    }

    func testFourOverviewsShareTheThermalNoticeProperty() throws {
        let files = [
            "Pulse/Views/OverviewSection.swift",
            "Pulse/Views/CPUOverviewSection.swift",
            "Pulse/Views/NetworkOverviewSection.swift",
            "Pulse/Views/DiskOverviewSection.swift",
        ]
        for file in files {
            let source = try repoText(file)
            XCTAssertTrue(source.contains("vm.thermalNotice"), file)
            XCTAssertFalse(source.contains("Timer"), file)
            XCTAssertFalse(source.contains("ProcessInfo"), file)
        }
    }

    /// Card above the fixed-height metric row on sampling and ready. The line stays only when advice is nil.
    func testFiveOverviewsPlaceAdviceAboveTheFixedMetricRow() throws {
        let overview = try repoText("Pulse/Views/OverviewSection.swift")
        let cpu = try repoText("Pulse/Views/CPUOverviewSection.swift")
        let network = try repoText("Pulse/Views/NetworkOverviewSection.swift")
        let disk = try repoText("Pulse/Views/DiskOverviewSection.swift")
        let machine = try repoText("Pulse/Views/MachineOverviewSection.swift")

        for (name, source) in [
            ("OverviewSection.swift", overview),
            ("CPUOverviewSection.swift", cpu),
            ("NetworkOverviewSection.swift", network),
            ("DiskOverviewSection.swift", disk),
            ("MachineOverviewSection.swift", machine),
        ] {
            XCTAssertFalse(source.contains("ThermalAdviceCard(advice:"), name)
            XCTAssertFalse(source.contains("onTerminate:"), name)
            XCTAssertFalse(source.contains("terminateThermalAdvice"), name)
            XCTAssertFalse(source.contains("private var thermalAdviceCard"), name)
            XCTAssertFalse(source.contains("ProcessActions"), name)
            XCTAssertFalse(source.contains("confirmForceQuit"), name)
            XCTAssertFalse(source.contains("quitSelected"), name)
            let failure = functionBodyIfPresent(named: "failureBody", in: source)
            XCTAssertFalse(failure.contains("thermalAdvice"), name)
            XCTAssertFalse(failure.contains("ThermalAdvice"), name)
            XCTAssertFalse(failure.contains("ThermalNoticeLine"), name)
        }

        XCTAssertEqual(occurrenceCount(of: ".frame(height: 148)", in: overview), 2)
        XCTAssertEqual(occurrenceCount(of: ".frame(height: 150)", in: cpu), 2)
        XCTAssertEqual(occurrenceCount(of: ".frame(height: 150)", in: network), 2)
        XCTAssertEqual(occurrenceCount(of: ".frame(height: 150)", in: disk), 2)
        XCTAssertEqual(occurrenceCount(of: ".frame(height: 192)", in: machine), 1)

        let memorySampling = try functionBody(named: "samplingBody", in: overview)
        let memoryReady = try functionBody(named: "readyBody", in: overview)
        try assertAdviceCardIsFirstRow(of: "VStack(spacing: 12)", in: memorySampling, height: ".frame(height: 148)")
        try assertAdviceCardIsFirstRow(of: "VStack(spacing: 12)", in: memoryReady, height: ".frame(height: 148)")
        XCTAssertEqual(occurrenceCount(of: "ThermalAdviceCard()", in: memorySampling), 1)
        XCTAssertEqual(occurrenceCount(of: "ThermalAdviceCard()", in: memoryReady), 1)
        let hero = try functionBody(named: "samplingHero", in: overview)
        XCTAssertFalse(hero.contains("ThermalAdviceCard"))
        XCTAssertFalse(hero.contains("thermalAdviceCard"))
        XCTAssertTrue(hero.contains("if vm.thermalAdvice == nil, let notice = vm.thermalNotice"))
        XCTAssertTrue(hero.contains("ThermalNoticeLine(text: notice)"))
        XCTAssertTrue(hero.contains(".frame(width: 168, alignment: .leading)"))
        XCTAssertTrue(memoryReady.contains("thermalNotice: vm.thermalAdvice == nil ? vm.thermalNotice : nil"))
        let cards = try repoText("Pulse/Views/OverviewCards.swift")
        XCTAssertTrue(cards.contains("if let thermalNotice {\n                        ThermalNoticeLine(text: thermalNotice)\n                    }"))

        for source in [cpu] {
            let sampling = try functionBody(named: "samplingBody", in: source)
            let ready = try functionBody(named: "readyBody", in: source)
            try assertAdviceCardIsFirstRow(of: "VStack(spacing: 12)", in: sampling, height: ".frame(height: 150)")
            try assertAdviceCardIsFirstRow(of: "VStack(spacing: 12)", in: ready, height: ".frame(height: 150)")
            for body in [sampling, ready] {
                let pulse = try braceBody(after: "PulseCard", in: body)
                XCTAssertFalse(pulse.contains("ThermalAdviceCard"))
                XCTAssertFalse(pulse.contains("thermalAdviceCard"))
                XCTAssertTrue(pulse.contains("if vm.thermalAdvice == nil, let notice = vm.thermalNotice"))
                XCTAssertTrue(pulse.contains("ThermalNoticeLine(text: notice)"))
                XCTAssertTrue(pulse.contains(".frame(width: 200, alignment: .leading)"))
                XCTAssertFalse(pulse.contains(".frame(height: 150)"))
            }
        }

        let networkSampling = try functionBody(named: "samplingBody", in: network)
        let networkReady = try functionBody(named: "readyBody", in: network)
        try assertAdviceCardIsFirstRow(of: "VStack(spacing: 12)", in: networkSampling, height: ".frame(height: 150)")
        try assertAdviceCardIsFirstRow(of: "VStack(spacing: 12)", in: networkReady, height: ".frame(height: 150)")
        assertInlineNoticeStaysOnFirstCard(networkSampling, firstTitle: "NetworkPageCopy.inboundTitle", secondTitle: "NetworkPageCopy.outboundTitle")
        assertInlineNoticeStaysOnFirstCard(networkReady, firstTitle: "NetworkPageCopy.inboundTitle", secondTitle: "NetworkPageCopy.outboundTitle")
        XCTAssertTrue(networkSampling.contains("samplingCard(title: NetworkPageCopy.outboundTitle, symbol: \"arrow.up\")"))
        let networkSamplingCard = try functionBody(named: "samplingCard", in: network)
        XCTAssertFalse(networkSamplingCard.contains("thermalAdvice"))
        XCTAssertFalse(networkSamplingCard.contains("ThermalAdviceCard"))
        XCTAssertTrue(networkSamplingCard.contains("if let thermalNotice {\n                        ThermalNoticeLine(text: thermalNotice)\n                    }"))
        XCTAssertTrue(networkSamplingCard.contains(".frame(width: 168, alignment: .leading)"))
        let networkRate = try typeBody(named: "NetworkRateCard", keyword: "struct", in: network)
        XCTAssertFalse(networkRate.contains("ThermalAdviceCard"))
        XCTAssertFalse(networkRate.contains("thermalAdvice"))
        XCTAssertTrue(networkRate.contains("if let thermalNotice {\n                        ThermalNoticeLine(text: thermalNotice)\n                    }"))
        XCTAssertTrue(networkRate.contains(".frame(width: 168, alignment: .leading)"))

        let diskSampling = try functionBody(named: "samplingBody", in: disk)
        let diskReady = try functionBody(named: "readyBody", in: disk)
        try assertAdviceCardIsFirstRow(of: "VStack(spacing: 12)", in: diskSampling, height: ".frame(height: 150)")
        try assertAdviceCardIsFirstRow(of: "VStack(spacing: 12)", in: diskReady, height: ".frame(height: 150)")
        assertInlineNoticeStaysOnFirstCard(diskSampling, firstTitle: "DiskPageCopy.readTitle", secondTitle: "DiskPageCopy.writeTitle")
        assertInlineNoticeStaysOnFirstCard(diskReady, firstTitle: "DiskPageCopy.readTitle", secondTitle: "DiskPageCopy.writeTitle")
        XCTAssertTrue(diskSampling.contains("samplingCard(title: DiskPageCopy.writeTitle, symbol: \"arrow.up\")"))
        let diskSamplingCard = try functionBody(named: "samplingCard", in: disk)
        XCTAssertFalse(diskSamplingCard.contains("thermalAdvice"))
        XCTAssertFalse(diskSamplingCard.contains("ThermalAdviceCard"))
        XCTAssertTrue(diskSamplingCard.contains("if let thermalNotice {\n                        ThermalNoticeLine(text: thermalNotice)\n                    }"))
        XCTAssertTrue(diskSamplingCard.contains(".frame(width: 168, alignment: .leading)"))
        let diskRate = try typeBody(named: "DiskRateCard", keyword: "struct", in: disk)
        XCTAssertFalse(diskRate.contains("ThermalAdviceCard"))
        XCTAssertFalse(diskRate.contains("thermalAdvice"))
        XCTAssertTrue(diskRate.contains("if let thermalNotice {\n                        ThermalNoticeLine(text: thermalNotice)\n                    }"))
        XCTAssertTrue(diskRate.contains(".frame(width: 168, alignment: .leading)"))

        let machineBody = try functionBody(named: "body", in: machine)
        try assertAdviceCardIsFirstRow(of: "VStack(alignment: .leading, spacing: 12)", in: machineBody, height: ".frame(height: 192)")
        XCTAssertLessThan(
            try index(of: "ThermalAdviceCard()", in: machineBody),
            try index(of: "identity(model)", in: machineBody)
        )
        let shared = try repoText("Pulse/Views/ThermalAdviceCard.swift")
        XCTAssertEqual(occurrenceCount(of: "struct ThermalAdviceCard", in: shared), 1)
        XCTAssertTrue(shared.contains("@EnvironmentObject private var vm: MemoryDashboardVM"))
        XCTAssertTrue(shared.contains("if let advice = vm.thermalAdvice"))
        XCTAssertEqual(occurrenceCount(of: "vm.terminateThermalAdvice(pid: pid)", in: shared), 1)
        XCTAssertEqual(occurrenceCount(of: "ThermalNotice.throttling", in: shared), 1)
        XCTAssertEqual(occurrenceCount(of: "ThermalAdvice.noHighLoadMessage", in: shared), 1)
        XCTAssertTrue(shared.contains("executablePath: process.executablePath"))
        XCTAssertFalse(shared.contains("ProcessActions"))
        XCTAssertFalse(shared.contains("confirmForceQuit"))
        let noLoad = try braceBody(after: "if advice.noHighLoad", in: shared)
        XCTAssertTrue(noLoad.contains("ThermalAdvice.noHighLoadMessage"))
        XCTAssertFalse(noLoad.contains("ThermalNotice"))
        XCTAssertFalse(noLoad.contains("ForEach"))
        XCTAssertLessThan(
            try index(of: "ThermalNotice.throttling", in: shared),
            try index(of: "ForEach(advice.processes", in: shared)
        )
        for (name, source) in [
            ("OverviewSection.swift", overview),
            ("CPUOverviewSection.swift", cpu),
            ("NetworkOverviewSection.swift", network),
            ("DiskOverviewSection.swift", disk),
            ("MachineOverviewSection.swift", machine),
        ] {
            XCTAssertGreaterThan(occurrenceCount(of: "ThermalAdviceCard()", in: source), 0, name)
        }
        let diagnostics = try functionBody(named: "diagnostics", in: machine)
        XCTAssertFalse(diagnostics.contains("ThermalAdviceCard"))
        XCTAssertFalse(diagnostics.contains("thermalAdviceCard"))
        XCTAssertTrue(diagnostics.contains("if vm.thermalAdvice == nil, let notice = model.thermalNotice"))
        XCTAssertTrue(diagnostics.contains("ThermalNoticeLine(text: notice)"))
        XCTAssertTrue(diagnostics.contains("in: Capsule()"))
        XCTAssertTrue(machine.contains("vm.thermalNotice"))
    }

    /// Every card click terminates that pid. A selected process-page pid finishes the session only when `ordinaryTerminate` issues one.
    func testTerminateThermalAdviceAlwaysTerminatesAndFinishesAnIssuedSelection() throws {
        let dashboard = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertFalse(dashboard.contains("terminateThermalAdvice"))
        XCTAssertFalse(dashboard.contains("func terminateThermalAdvice"))

        let advice = try repoText("Pulse/ViewModels/MemoryDashboardVM+ThermalAdvice.swift")
        XCTAssertFalse(advice.contains("confirmForceQuit"))
        XCTAssertFalse(advice.contains("quitSelected"))
        XCTAssertFalse(advice.contains("selectedEnergyExitedOnly"))
        XCTAssertFalse(advice.contains("forceTerminate"))
        XCTAssertFalse(advice.contains("addObserver"))
        XCTAssertEqual(occurrenceCount(of: "func terminateThermalAdvice(pid: Int32) async", in: advice), 1)

        XCTAssertFalse(advice.contains("selectedPid ="))
        let method = try functionBody(named: "terminateThermalAdvice", in: advice)
        XCTAssertTrue(method.contains("beginThermalTerminate(pid: pid)"))
        XCTAssertFalse(method.contains("ProcessActions"))
        XCTAssertFalse(method.contains("ordinaryTerminate"))
        XCTAssertFalse(method.contains("selectedEnergyExitedOnly"))
        XCTAssertFalse(method.contains("quitSelected"))
        XCTAssertFalse(method.contains("confirmForceQuit"))

        let core = try functionBody(
            named: "beginThermalTerminate",
            in: try repoText("Pulse/Models/DashboardCore+Quit.swift")
        )
        XCTAssertTrue(core.contains("pid == selectedPid"))
        XCTAssertTrue(core.contains("selectedPage.allowsProcessQuit"))
        XCTAssertTrue(core.contains("ProcessQuitSession.ordinaryTerminate("))
        XCTAssertTrue(core.contains("usedBytes: quitReleaseBaseline"))
        XCTAssertTrue(core.contains(".terminate(pid: pid, force: false"))
        XCTAssertFalse(core.contains("selectedPid ="))
        XCTAssertFalse(core.contains("confirmForceQuit"))
        XCTAssertFalse(core.contains("selectedEnergyExitedOnly"))
        XCTAssertFalse(core.contains("quitSelected"))
        XCTAssertLessThan(
            try index(of: "selectedPage.allowsProcessQuit", in: core),
            try index(of: "ProcessQuitSession.ordinaryTerminate(", in: core)
        )
        XCTAssertLessThan(
            try index(of: "ProcessQuitSession.ordinaryTerminate(", in: core),
            try index(of: ".terminate(pid: pid, force: false", in: core)
        )
        let issueGate = try braceBody(after: "if pid == selectedPid", in: core)
        XCTAssertTrue(issueGate.contains("ProcessQuitSession.ordinaryTerminate("))
        XCTAssertFalse(issueGate.contains(".terminate(pid: pid"))

        let perform = try functionBody(named: "performExternal", in: dashboard)
        XCTAssertEqual(occurrenceCount(of: "ProcessActions.terminate(pid: pid)", in: perform), 1)
        XCTAssertTrue(perform.contains("ProcessActions.forceTerminate(pid: pid)"))
        XCTAssertTrue(perform.contains("finishQuit("))
        XCTAssertTrue(perform.contains("pid: pid"))
        XCTAssertTrue(perform.contains("token: token"))
        XCTAssertTrue(perform.contains("result: result"))
        XCTAssertTrue(perform.contains("taskCancelled: Task.isCancelled"))
        XCTAssertLessThan(
            try index(of: "ProcessActions.terminate(pid: pid)", in: perform),
            try index(of: "finishQuit(", in: perform)
        )
        let finishGate = try braceBody(after: "if let token", in: perform)
        XCTAssertTrue(finishGate.contains("finishQuit("))
        XCTAssertFalse(finishGate.contains("ProcessActions.terminate"))
        XCTAssertEqual(occurrenceCount(of: "addObserver", in: try WiringSourceText.text(for: "MemoryDashboardVM")), 1)
    }

    func testAdviceRowUsesExecutablePathWhenTheRunningAppHasNoIcon() throws {
        let shared = try repoText("Pulse/Views/SharedUI.swift")
        XCTAssertTrue(shared.contains("var executablePath: String? = nil"))
        let icon = try functionBody(named: "resolvedIcon", in: shared)
        XCTAssertTrue(icon.contains("NSRunningApplication(processIdentifier: pid)"))
        XCTAssertTrue(icon.contains("runningApplications(withBundleIdentifier: bundleIdentifier)"))
        XCTAssertTrue(icon.contains("!executablePath.isEmpty"))
        XCTAssertTrue(icon.contains("NSWorkspace.shared.icon(forFile: executablePath)"))
        XCTAssertLessThan(
            try index(of: "NSRunningApplication(processIdentifier: pid)", in: icon),
            try index(of: "NSWorkspace.shared.icon(forFile: executablePath)", in: icon)
        )
        XCTAssertLessThan(
            try index(of: "runningApplications(withBundleIdentifier: bundleIdentifier)", in: icon),
            try index(of: "NSWorkspace.shared.icon(forFile: executablePath)", in: icon)
        )
        let card = try repoText("Pulse/Views/ThermalAdviceCard.swift")
        XCTAssertTrue(card.contains("executablePath: process.executablePath"))
        let preview = try repoText("Pulse/Views/SnapshotExportPreview.swift")
        XCTAssertFalse(preview.contains("NSWorkspace"))
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

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        try range(of: needle, in: source).lowerBound
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = [
            "var \(name):",
            "func \(name)(",
            "func \(name)()",
            "private func \(name)(",
            "private func \(name)()",
        ]
        for pattern in patterns {
            guard let found = source.range(of: pattern),
                  let brace = source[found.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw ThermalNoticeSourceError.missing("declaration for \(name)")
    }

    private func functionBodyIfPresent(named name: String, in source: String) -> String {
        (try? functionBody(named: name, in: source)) ?? ""
    }

    private func typeBody(named name: String, keyword: String, in source: String) throws -> String {
        guard let start = source.range(of: "\(keyword) \(name)")?.lowerBound else {
            throw ThermalNoticeSourceError.missing("\(keyword) \(name)")
        }
        guard let brace = source[start...].firstIndex(of: "{") else {
            throw ThermalNoticeSourceError.missing("body for \(name)")
        }
        return try balancedSlice(from: brace, in: source, label: name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let found = source.range(of: needle) else {
            throw ThermalNoticeSourceError.missing(needle)
        }
        guard let brace = source[found.upperBound...].firstIndex(of: "{") else {
            throw ThermalNoticeSourceError.missing("brace after \(needle)")
        }
        return try balancedSlice(from: brace, in: source, label: needle)
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        let opener = source[start]
        let closer: Character = opener == "(" ? ")" : "}"
        var depth = 0
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == opener { depth += 1 }
            if character == closer {
                depth -= 1
                if depth == 0 {
                    return String(source[start...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }
        throw ThermalNoticeSourceError.missing("balanced \(opener) for \(label)")
    }

    private func compact(_ source: String) -> String {
        source.filter { !$0.isWhitespace }
    }

    private func assertAdviceCardIsFirstRow(
        of vstack: String,
        in source: String,
        height: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let column = try braceBody(after: vstack, in: source)
        XCTAssertTrue(compact(column).hasPrefix("{ThermalAdviceCard()"), "advice card is the first row", file: file, line: line)
        XCTAssertEqual(occurrenceCount(of: "ThermalAdviceCard()", in: column), 1, file: file, line: line)
        XCTAssertTrue(column.contains(height), "fixed height stays on the metric row", file: file, line: line)
        guard let columnRange = source.range(of: column) else {
            throw ThermalNoticeSourceError.missing("placed column")
        }
        XCTAssertFalse(source[columnRange.upperBound...].contains(height), "fixed height must not wrap the advice card", file: file, line: line)
    }

    private func assertInlineNoticeStaysOnFirstCard(
        _ body: String,
        firstTitle: String,
        secondTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let gate = "vm.thermalAdvice == nil ? vm.thermalNotice : nil"
        XCTAssertEqual(occurrenceCount(of: gate, in: body), 1, file: file, line: line)
        let parts = body.components(separatedBy: secondTitle)
        XCTAssertEqual(parts.count, 2, file: file, line: line)
        XCTAssertTrue(parts[0].contains(firstTitle), file: file, line: line)
        XCTAssertTrue(parts[0].contains(gate), file: file, line: line)
        XCTAssertFalse(parts[1].contains("thermalNotice"), file: file, line: line)
        XCTAssertFalse(parts[1].contains("ThermalNoticeLine"), file: file, line: line)
        XCTAssertFalse(parts[1].contains("ThermalAdvice"), file: file, line: line)
    }

    private func range(of needle: String, in source: String) throws -> Range<String.Index> {
        guard let found = source.range(of: needle) else {
            XCTFail("missing \(needle)")
            throw ThermalNoticeSourceError.missing(needle)
        }
        return found
    }
}

private enum ThermalNoticeSourceError: Error {
    case missing(String)
}
