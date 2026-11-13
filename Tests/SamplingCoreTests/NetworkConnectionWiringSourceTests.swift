import XCTest

/// Source locks for the network connection card. Linux does not start a path monitor.
final class NetworkConnectionWiringSourceTests: XCTestCase {
    func testCardSitsBetweenAdviceAndTheRateRow() throws {
        let source = try repoText("Pulse/Views/NetworkOverviewSection.swift")
        let sampling = try functionBody(named: "samplingBody", in: source)
        let ready = try functionBody(named: "readyBody", in: source)
        let failure = try functionBody(named: "failureBody", in: source)

        try assertCard(
            in: sampling,
            call: "NetworkConnectionCardView(placeholder: true)",
            before: "samplingCard("
        )
        try assertCard(
            in: ready,
            call: "NetworkConnectionCardView(placeholder: false)",
            before: "NetworkRateCard("
        )
        XCTAssertFalse(failure.contains("NetworkConnectionCardView"))
        XCTAssertEqual(occurrenceCount(of: ".frame(height: 150)", in: source), 2)
    }

    func testSamplingPlaceholderDoesNotReadThePath() throws {
        let view = try repoText("Pulse/Views/NetworkConnectionCardView.swift")
        XCTAssertTrue(view.contains("NetworkPageCopy.connectionTitle"))
        XCTAssertTrue(view.contains("PulseCard"))
        XCTAssertTrue(view.contains("Image(systemName:"))
        let skeleton = try braceBody(after: "if placeholder", in: view)
        XCTAssertTrue(skeleton.contains("SkeletonBlock"))
        XCTAssertFalse(skeleton.contains("hostConnection"))
        XCTAssertFalse(skeleton.contains("hostWiFi"))
        XCTAssertFalse(skeleton.contains("NetworkConnectionCard.project"))
        XCTAssertTrue(view.contains("NetworkConnectionCard.project(vm.hostConnection, wifi: vm.hostWiFi, ssidPermission: vm.ssidPermission)"))
        XCTAssertFalse(view.contains("Timer"))
    }

    func testPathMonitorPushesWithoutATimerOrTheSampler() throws {
        let monitor = try repoText("Pulse/Sampling/HostConnectionMonitor.swift")
        XCTAssertTrue(monitor.contains("NWPathMonitor"))
        XCTAssertTrue(monitor.contains("queue: .main"))
        XCTAssertFalse(monitor.contains("Timer"))

        let watch = try repoText("Pulse/ViewModels/MemoryDashboardVM+NetworkConnection.swift")
        XCTAssertTrue(watch.contains("func beginConnectionWatch()"))
        XCTAssertTrue(watch.contains("func endConnectionWatch()"))
        XCTAssertFalse(watch.contains("Timer"))
        XCTAssertFalse(watch.contains("Task.sleep"))

        let dashboard = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(dashboard.contains("beginConnectionWatch()"))
        XCTAssertTrue(dashboard.contains("endConnectionWatch()"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("HostConnectionMonitor"))
        XCTAssertFalse(sampler.contains("HostConnection"))
        let models = try repoText("Pulse/Models/MemoryModels.swift")
        XCTAssertFalse(models.contains("HostConnection"))
    }

    func testMappingStaysPortableAndTheMonitorStaysOutOfSources() throws {
        let mapping = try repoText("Pulse/Sampling/HostConnection.swift")
        XCTAssertTrue(mapping.contains("import Foundation"))
        for token in ["import Network", "import Darwin", "import AppKit", "import SwiftUI", "NWPathMonitor", "Timer"] {
            XCTAssertFalse(mapping.contains(token), token)
        }

        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("\"Sampling/HostConnectionMonitor.swift\""))
        XCTAssertTrue(parts[1].contains("\"Sampling/HostConnection.swift\""))
        XCTAssertTrue(parts[1].contains("\"Models/NetworkConnectionCard.swift\""))
        XCTAssertFalse(parts[1].contains("HostConnectionMonitor.swift"))
        XCTAssertFalse(parts[1].contains("NetworkConnectionCardView.swift"))
        XCTAssertFalse(parts[1].contains("MemoryDashboardVM+NetworkConnection.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        for name in [
            "HostConnection.swift in Sources",
            "HostConnectionMonitor.swift in Sources",
            "NetworkConnectionCard.swift in Sources",
            "NetworkConnectionCardView.swift in Sources",
            "MemoryDashboardVM+NetworkConnection.swift in Sources",
        ] {
            XCTAssertTrue(project.contains(name), name)
        }
    }

    func testNetworkOverviewGrowsForTheConnectionCard() throws {
        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        let height = try functionBody(named: "overviewHeight", in: dashboard)
        XCTAssertFalse(height.contains("case .cpu, .network, .disk:"))
        XCTAssertTrue(height.contains("case .network:"))
        // Wi-Fi adds the SSID row. Placeholder or non-Wi-Fi is 148; Wi-Fi is 206.
        // The clipped slot is 368 (206 + 12 + 150) so the spare gap stays under the rate charts.
        XCTAssertTrue(height.contains("368"))
        XCTAssertFalse(height.contains("336"))
        XCTAssertFalse(height.contains("274"))
        XCTAssertFalse(height.contains("300"))
        XCTAssertFalse(height.contains("310"))
        XCTAssertTrue(dashboard.contains("alignment: .top"))
        let card = try repoText("Pulse/Views/NetworkConnectionCardView.swift")
        XCTAssertTrue(card.contains("206"))
        XCTAssertTrue(card.contains("148"))
        XCTAssertFalse(card.contains("174"))
        XCTAssertFalse(card.contains("112"))
        XCTAssertFalse(card.contains("138"))
        XCTAssertTrue(card.contains("alignment: .top"))
    }

    func testWiFiSignalIsReadOnceFromSampleWithoutATimer() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        let sample = try functionBody(named: "sample", in: sampler)
        let call = try lineContaining("HostWiFiReader.read()", in: sampler)
        XCTAssertTrue(sample.contains("HostWiFiReader.read()"))
        XCTAssertEqual(occurrenceCount(of: "HostWiFiReader.read()", in: sampler), 1)
        XCTAssertFalse(call.contains("Timer"))
        XCTAssertFalse(sample.contains("Timer"))

        let reader = try repoText("Pulse/Sampling/HostWiFiReader.swift")
        XCTAssertFalse(reader.contains("Timer"))
        XCTAssertTrue(reader.contains("interface.ssid()"))
        XCTAssertTrue(reader.contains("HostWiFiLocation.currentPermission()"))
        XCTAssertTrue(reader.contains(".authorized"))
        XCTAssertFalse(reader.contains("requestWhenInUseAuthorization"))
        XCTAssertFalse(reader.contains("requestAlwaysAuthorization"))
        XCTAssertTrue(reader.contains("CWWiFiClient.shared().interface()"))
        XCTAssertTrue(reader.contains("rssiValue()"))
        XCTAssertTrue(reader.contains("noiseMeasurement()"))

        let portable = try repoText("Pulse/Sampling/HostWiFi.swift")
        XCTAssertTrue(portable.contains("import Foundation"))
        XCTAssertTrue(portable.contains("enum WiFiSSIDPermission"))
        for token in ["import CoreWLAN", "import CoreLocation", "import Darwin", "import AppKit", "import SwiftUI"] {
            XCTAssertFalse(portable.contains(token), token)
        }

        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[1].contains("\"Sampling/HostWiFi.swift\""))
        XCTAssertTrue(parts[0].contains("\"Sampling/HostWiFiReader.swift\""))
        XCTAssertFalse(parts[1].contains("HostWiFiReader.swift"))
    }

    func testPublicIPLookupRunsOnlyFromTheButton() throws {
        let card = try repoText("Pulse/Views/NetworkConnectionCardView.swift")
        let query = try braceBody(after: "Button(PublicIPCopy.query)", in: card)
        let retry = try braceBody(after: "Button(PublicIPCopy.retry)", in: card)
        XCTAssertTrue(query.contains("vm.requestPublicIP()"))
        XCTAssertTrue(retry.contains("vm.requestPublicIP()"))
        let skeleton = try braceBody(after: "if placeholder", in: card)
        XCTAssertFalse(skeleton.contains("requestPublicIP"))
        XCTAssertFalse(skeleton.contains("PublicIPLookup"))
        XCTAssertFalse(skeleton.contains("Button("))
        XCTAssertTrue(card.contains("NSPasteboard.general"))
        XCTAssertTrue(card.contains("TimeZone.current"))
        let label = try functionBody(named: "accessibilityLabel", in: card)
        XCTAssertTrue(label.contains("address"))
        XCTAssertTrue(label.contains("PublicIPCopy.failed"))
        XCTAssertFalse(card.contains("ConnectionInterface"))
        XCTAssertFalse(card.contains(".ethernet"))
        XCTAssertFalse(card.contains(".wifi"))

        let action = try repoText("Pulse/ViewModels/MemoryDashboardVM+NetworkConnection.swift")
        let request = try functionBody(named: "requestPublicIP", in: action)
        XCTAssertTrue(request.contains("requestPublicIP(now:"))
        XCTAssertFalse(request.contains("PublicIPLookup.lookup"))
        XCTAssertFalse(action.contains("NSPasteboard"))
        XCTAssertFalse(action.contains("Timer"))
        let watch = try functionBody(named: "beginConnectionWatch", in: action)
        XCTAssertFalse(watch.contains("PublicIP"))
        XCTAssertFalse(watch.contains("requestPublicIP"))
        XCTAssertFalse(watch.contains("ipify"))
        XCTAssertFalse(watch.contains("checkip"))

        let dashboard = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let perform = try functionBody(named: "perform", in: dashboard)
        XCTAssertEqual(occurrenceCount(of: "PublicIPLookup.lookup", in: dashboard), 1)
        XCTAssertTrue(perform.contains("PublicIPLookup.lookup"))
        let initial = try initializerBody(in: dashboard)
        XCTAssertFalse(initial.contains("PublicIP"))
        XCTAssertFalse(initial.contains("requestPublicIP"))
        XCTAssertFalse(initial.contains("ipify"))
        let start = try functionBody(named: "start", in: dashboard)
        XCTAssertFalse(start.contains("PublicIP"))
        XCTAssertFalse(start.contains("requestPublicIP"))

        let model = try repoText("Pulse/Models/PublicIPLookup.swift")
        XCTAssertFalse(model.contains("TimeZone.current"))
        XCTAssertFalse(model.contains("import AppKit"))
        XCTAssertFalse(model.contains("import Network"))
        XCTAssertFalse(model.contains("NSPasteboard"))

        for relative in [
            "Pulse/Sampling/MemorySampler.swift",
            "Pulse/PulseApp.swift",
            "Pulse/MenuBar/PulseAppDelegate.swift",
        ] {
            let text = try repoText(relative)
            for token in ["PublicIPLookup", "requestPublicIP", "PublicIP", "ipify", "checkip"] {
                XCTAssertFalse(text.contains(token), "\(relative) \(token)")
            }
        }
    }

    func testPublicIPTransportIsEphemeralAndExcluded() throws {
        let transport = try repoText("Pulse/Sampling/PublicIPURLSessionTransport.swift")
        XCTAssertTrue(transport.contains("URLSessionConfiguration.ephemeral"))
        XCTAssertTrue(transport.contains("timeoutIntervalForRequest = 8"))

        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("\"Sampling/PublicIPURLSessionTransport.swift\""))
        XCTAssertFalse(parts[1].contains("PublicIPURLSessionTransport.swift"))
        XCTAssertTrue(parts[1].contains("\"Models/PublicIPLookup.swift\""))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("PublicIPLookup.swift in Sources"))
        XCTAssertTrue(project.contains("PublicIPURLSessionTransport.swift in Sources"))
    }

    func testSnapshotsAndMenuBarDoNotMentionPublicIP() throws {
        var files = [
            "Pulse/Models/SnapshotExport.swift",
            "Pulse/Models/SnapshotExportFile.swift",
            "Pulse/ViewModels/MemoryDashboardVM+SnapshotExport.swift",
            "Pulse/Views/SnapshotExportPreview.swift",
        ]
        let menuBar = repoRoot().appendingPathComponent("Pulse/MenuBar", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(at: menuBar, includingPropertiesForKeys: nil)
        files += entries
            .filter { $0.pathExtension == "swift" }
            .map { "Pulse/MenuBar/\($0.lastPathComponent)" }
        for relative in files {
            let text = try repoText(relative)
            for token in ["PublicIP", "ipify", "checkip", "HostWiFi", "ssid", "CLLocation"] {
                XCTAssertFalse(text.contains(token), "\(relative) \(token)")
            }
        }
    }

    func testSSIDPromptIsOnlyTheAllowButton() throws {
        let pulse = repoRoot().appendingPathComponent("Pulse", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: pulse, includingPropertiesForKeys: nil) else {
            throw NetworkConnectionSourceError.missing("Pulse")
        }
        var sawLocationFile = false
        for case let url as URL in enumerator {
            guard ["swift", "plist", "entitlements"].contains(url.pathExtension) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if url.lastPathComponent == "HostWiFiLocation.swift" {
                sawLocationFile = true
                continue
            }
            XCTAssertFalse(text.contains("requestWhenInUseAuthorization"), url.path)
        }
        XCTAssertTrue(sawLocationFile)

        let location = try repoText("Pulse/Sampling/HostWiFiLocation.swift")
        XCTAssertEqual(occurrenceCount(of: "requestWhenInUseAuthorization", in: location), 1)
        let request = try functionBody(named: "request", in: location)
        XCTAssertTrue(request.contains("requestWhenInUseAuthorization()"))
        XCTAssertFalse(location.replacingOccurrences(of: request, with: "").contains("requestWhenInUseAuthorization"))
        let started = try functionBody(named: "start", in: location)
        XCTAssertFalse(started.contains("requestWhenInUseAuthorization"))
        XCTAssertFalse(started.contains(".request()"))
        XCTAssertFalse(location.contains("Timer"))
        XCTAssertTrue(location.contains("import CoreLocation"))
        XCTAssertTrue(location.contains("locationManagerDidChangeAuthorization"))
        XCTAssertTrue(location.contains("MainActor.assumeIsolated"))
        XCTAssertTrue(location.contains("case .notDetermined"))
        XCTAssertTrue(location.contains("case .denied, .restricted"))
        XCTAssertTrue(location.contains("case .authorizedAlways, .authorizedWhenInUse"))
        XCTAssertFalse(location.contains("case .authorized,"))
        XCTAssertFalse(location.contains("requestAlwaysAuthorization"))

        let card = try repoText("Pulse/Views/NetworkConnectionCardView.swift")
        let allow = try braceBody(after: "Button(NetworkPageCopy.ssidAllow)", in: card)
        XCTAssertTrue(allow.contains("vm.allowWiFiSSID()"))
        XCTAssertTrue(card.contains(".lineLimit(1)"))
        XCTAssertTrue(card.contains(".truncationMode(.middle)"))
        XCTAssertTrue(card.contains(".help("))
        let skeleton = try braceBody(after: "if placeholder", in: card)
        XCTAssertFalse(skeleton.contains("allowWiFiSSID"))
        XCTAssertFalse(skeleton.contains("ssidAllow"))

        let action = try repoText("Pulse/ViewModels/MemoryDashboardVM+NetworkConnection.swift")
        let allowBody = try functionBody(named: "allowWiFiSSID", in: action)
        XCTAssertTrue(allowBody.contains("allowWiFiSSID()"))
        XCTAssertFalse(allowBody.contains("HostWiFiLocation.request()"))
        XCTAssertFalse(allowBody.contains("requestWhenInUseAuthorization"))
        let watch = try functionBody(named: "startWiFiSSIDWatch", in: action)
        XCTAssertTrue(watch.contains("HostWiFiLocation.start"))
        XCTAssertFalse(watch.contains("allowWiFiSSID"))
        XCTAssertFalse(watch.contains(".request()"))
        XCTAssertFalse(watch.contains("requestWhenInUseAuthorization"))

        let dashboard = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let perform = try functionBody(named: "perform", in: dashboard)
        XCTAssertEqual(occurrenceCount(of: "HostWiFiLocation.request()", in: dashboard), 1)
        XCTAssertTrue(perform.contains("HostWiFiLocation.request()"))
        let initial = try initializerBody(in: dashboard)
        XCTAssertFalse(initial.contains("allowWiFiSSID"))
        XCTAssertFalse(initial.contains("requestWhenInUseAuthorization"))
        let connectionWatch = try index(of: "beginConnectionWatch()", in: initial)
        let ssidWatch = try index(of: "startWiFiSSIDWatch()", in: initial)
        XCTAssertLessThan(connectionWatch, ssidWatch)

        for relative in [
            "Pulse/Sampling/MemorySampler.swift",
            "Pulse/PulseApp.swift",
            "Pulse/MenuBar/PulseAppDelegate.swift",
        ] {
            let text = try repoText(relative)
            XCTAssertFalse(text.contains("allowWiFiSSID"), relative)
            XCTAssertFalse(text.contains("requestWhenInUseAuthorization"), relative)
        }

        let reader = try repoText("Pulse/Sampling/HostWiFiReader.swift")
        XCTAssertFalse(reader.contains("requestWhenInUseAuthorization"))
        XCTAssertFalse(reader.contains("requestAlwaysAuthorization"))

        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("\"Sampling/HostWiFiLocation.swift\""))
        XCTAssertFalse(parts[1].contains("HostWiFiLocation.swift"))
        XCTAssertTrue(parts[1].contains("\"Sampling/HostWiFi.swift\""))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("HostWiFiLocation.swift in Sources"))

        let entitlements = try repoText("Pulse/Pulse.entitlements")
        XCTAssertTrue(entitlements.contains("com.apple.security.personal-information.location"))
        XCTAssertFalse(entitlements.contains("<dict/>"))
        let info = try repoText("Pulse/Info.plist")
        XCTAssertTrue(info.contains("<key>NSLocationUsageDescription</key>"))
        XCTAssertTrue(info.contains("<key>NSLocationWhenInUseUsageDescription</key>"))
        XCTAssertEqual(
            occurrenceCount(of: "用来显示当前 Wi-Fi 的名称。Pulse 不保存位置，也不把位置用于其它功能。", in: info),
            2
        )
    }

    private func lineContaining(_ needle: String, in source: String) throws -> String {
        guard let line = source.split(separator: "\n", omittingEmptySubsequences: false).first(where: { $0.contains(needle) }) else {
            throw NetworkConnectionSourceError.missing(needle)
        }
        return String(line)
    }

    private func assertCard(in body: String, call: String, before rateCall: String) throws {
        let advice = try index(of: "ThermalAdviceCard()", in: body)
        let card = try index(of: call, in: body)
        let rates = try index(of: rateCall, in: body)
        let stack = try index(of: "HStack(spacing: 12)", in: body)
        XCTAssertLessThan(advice, card)
        XCTAssertLessThan(card, stack)
        XCTAssertLessThan(stack, rates)
        let row = try braceBody(after: "HStack(spacing: 12)", in: body)
        XCTAssertFalse(row.contains("NetworkConnectionCardView"))
        XCTAssertEqual(occurrenceCount(of: call, in: body), 1)
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
        guard let found = source.range(of: needle)?.lowerBound else {
            throw NetworkConnectionSourceError.missing(needle)
        }
        return found
    }

    private func initializerBody(in source: String) throws -> String {
        guard let found = source.range(of: "init() {") else {
            throw NetworkConnectionSourceError.missing("init()")
        }
        let brace = source.index(before: found.upperBound)
        return try balancedSlice(from: brace, in: source, label: "init")
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = [
            "var \(name):",
            "func \(name)(",
            "private func \(name)(",
            "private func \(name)()",
        ]
        for pattern in patterns {
            guard let found = source.range(of: pattern),
                  let brace = source[found.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw NetworkConnectionSourceError.missing(name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let found = source.range(of: needle) else {
            throw NetworkConnectionSourceError.missing(needle)
        }
        guard let brace = source[found.upperBound...].firstIndex(of: "{") else {
            throw NetworkConnectionSourceError.missing("brace after \(needle)")
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
        throw NetworkConnectionSourceError.missing("balanced \(opener) for \(label)")
    }
}

private enum NetworkConnectionSourceError: Error {
    case missing(String)
}
