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
        XCTAssertTrue(view.contains("NetworkConnectionCard.project(vm.hostConnection, wifi: vm.hostWiFi)"))
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
        XCTAssertTrue(height.contains("300"))
        XCTAssertTrue(dashboard.contains("alignment: .top"))
        let card = try repoText("Pulse/Views/NetworkConnectionCardView.swift")
        XCTAssertTrue(card.contains("138"))
        XCTAssertTrue(card.contains("112"))
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
        XCTAssertFalse(reader.contains("ssid"))
        XCTAssertTrue(reader.contains("CWWiFiClient.shared().interface()"))
        XCTAssertTrue(reader.contains("rssiValue()"))
        XCTAssertTrue(reader.contains("noiseMeasurement()"))

        let portable = try repoText("Pulse/Sampling/HostWiFi.swift")
        XCTAssertTrue(portable.contains("import Foundation"))
        for token in ["import CoreWLAN", "import Darwin", "import AppKit", "import SwiftUI"] {
            XCTAssertFalse(portable.contains(token), token)
        }

        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[1].contains("\"Sampling/HostWiFi.swift\""))
        XCTAssertTrue(parts[0].contains("\"Sampling/HostWiFiReader.swift\""))
        XCTAssertFalse(parts[1].contains("HostWiFiReader.swift"))
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
