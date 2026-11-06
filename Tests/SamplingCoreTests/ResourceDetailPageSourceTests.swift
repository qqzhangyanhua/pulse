import XCTest

/// Phase 18 source constraints. Linux reads text; it does not compile the app,
/// enter SwiftUI, or click the sidebar. A pass is not a Mac build or a GUI check.
final class ResourceDetailPageSourceTests: XCTestCase {
    func testMemoryBranchKeepsThePhase17OrderAndFieldBody() throws {
        let presentation = try repoText("Pulse/Models/MemoryDetailPresentation.swift")
        let field = try functionBody(named: "field", in: presentation)
        XCTAssertTrue(field.contains("let title = page == .memory ? \"驻留内存\" : \"内存\""))
        XCTAssertTrue(field.contains("guard let total, total > 0 else"))
        XCTAssertTrue(field.contains("占物理内存的 \\(share)（按驻留内存计算）"))
        XCTAssertTrue(field.contains("ByteFormat.share(part: part, total: total)"))
        XCTAssertFalse(field.contains("lastLive"))
        XCTAssertFalse(field.contains("FrozenMemory"))
        XCTAssertFalse(field.contains("ResourceDetail"))

        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        XCTAssertEqual(occurrenceCount(of: "DisclosureGroup(", in: sidebar), 1)
        let cpuChart = try functionBody(named: "cpuChart", in: sidebar)
        XCTAssertTrue(cpuChart.contains("title: \"CPU\""))
        XCTAssertTrue(cpuChart.contains("正在采集 CPU 曲线"))

        let detail = try functionBody(named: "detailBody", in: sidebar)
        let memoryStart = try index(of: "case .memoryExisting", in: detail)
        let cpuCase = try index(of: "case .cpu", in: detail)
        let memoryBranch = String(detail[memoryStart..<cpuCase])
        let slot = try index(of: "vm.memoryGrowthSlot", in: memoryBranch)
        let gate = try index(of: "vm.sidebar.showsLiveTrend && vm.selectedPage == .memory", in: memoryBranch)
        let disclosure = try index(of: "samplingWindowDisclosure", in: memoryBranch)
        let memoryChart = try index(of: "memoryChart(detail)", in: memoryBranch)
        let cpu = try index(of: "cpuChart(detail)", in: memoryBranch)
        XCTAssertLessThan(slot, gate)
        XCTAssertLessThan(gate, disclosure)
        XCTAssertLessThan(disclosure, memoryChart)
        XCTAssertLessThan(memoryChart, cpu)
        XCTAssertTrue(memoryBranch.contains("metrics(detail)"))
        XCTAssertEqual(occurrenceCount(of: "samplingWindowDisclosure", in: memoryBranch), 1)
        XCTAssertEqual(occurrenceCount(of: "samplingWindowDisclosure", in: detail), 1)

        let untouched = try functionBody(named: "noResourceUpgradeDetail", in: sidebar)
        XCTAssertTrue(untouched.contains("metrics(detail)"))
        XCTAssertTrue(untouched.contains("memoryChart(detail)"))
        XCTAssertFalse(untouched.contains("samplingWindowDisclosure"))
        XCTAssertFalse(untouched.contains("cpuChart"))
        XCTAssertFalse(untouched.contains("memoryGrowthSlot"))
        XCTAssertFalse(untouched.contains("DisclosureGroup"))
        XCTAssertFalse(untouched.contains("驻留内存"))
    }

    func testResourceBranchesDoNotBorrowHostSeriesOrQuitState() throws {
        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        let network = try functionBody(named: "networkResourceDetail", in: sidebar)
        XCTAssertTrue(network.contains("ResourceDetailPageProjection.processNetworkUnavailable"))
        XCTAssertTrue(network.contains(".help(NetworkPageCopy.processRateHelp)"))
        XCTAssertEqual(occurrenceCount(of: "NetworkPageCopy", in: network), 1)
        for word in ["hostNetworkRates", "networkHistory", "cpuChart", "inbound", "0 字节", "DiskRateText"] {
            XCTAssertFalse(network.contains(word), word)
        }

        let disk = try functionBody(named: "diskResourceDetail", in: sidebar)
        XCTAssertTrue(disk.contains("diskRateMetric(title: DiskPageCopy.readTitle, bytesPerSecond: disk.readBytesPerSecond)"))
        XCTAssertTrue(disk.contains("diskRateMetric(title: DiskPageCopy.writeTitle, bytesPerSecond: disk.writeBytesPerSecond)"))
        XCTAssertFalse(disk.contains("readTitle, bytesPerSecond: disk.writeBytesPerSecond"))
        XCTAssertFalse(disk.contains("writeTitle, bytesPerSecond: disk.readBytesPerSecond"))
        for word in ["hostDiskRates", "diskHistory", "DiskRateCard", "cpuChart", "arrow.down", "arrow.up"] {
            XCTAssertFalse(disk.contains(word), word)
        }
        XCTAssertTrue(disk.contains("memoryChart(detail)"))

        for word in [
            "hostNetworkRates", "networkHistory", "hostDiskRates", "diskHistory", "DiskRateCard",
            "frozenDetail", "quitOutcome", "evaluate(", "selectedPid == nil", "selectedPid =",
        ] {
            XCTAssertFalse(sidebar.contains(word), word)
        }
        XCTAssertEqual(occurrenceCount(of: "DisclosureGroup(", in: sidebar), 1)
    }

    func testLastLiveWritesStayOnTheSidebarCallbacks() throws {
        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        let body = try functionBody(named: "body", in: sidebar)
        XCTAssertFalse(body.contains("lastLiveTotal ="))
        XCTAssertTrue(body.contains(".onAppear(perform: acceptCurrentSidebarLiveTotal)"))
        XCTAssertTrue(body.contains(".task { acceptCurrentSidebarLiveTotal() }"))
        XCTAssertTrue(body.contains("onChange(of: vm.snapshot)"))
        XCTAssertTrue(body.contains("acceptSnapshotTotal()"))
        XCTAssertTrue(body.contains("onChange(of: sidebarSubjectBeat)"))
        XCTAssertTrue(body.contains("acceptSidebarBeat(previous: previous, current: current)"))

        let reducer = try functionBody(named: "reduceLastLive", in: sidebar)
        XCTAssertTrue(reducer.contains("lastLiveTotal = LastLiveTotalReducer.step(lastLiveTotal, event)"))
        XCTAssertEqual(occurrenceCount(of: "reduceLastLive(", in: sidebar), 3)
        let appear = try functionBody(named: "acceptCurrentSidebarLiveTotal", in: sidebar)
        let sidebarBeat = try functionBody(named: "acceptSidebarBeat", in: sidebar)
        XCTAssertTrue(appear.contains("reduceLastLive("))
        XCTAssertTrue(sidebarBeat.contains("reduceLastLive("))
        XCTAssertTrue(sidebarBeat.contains("snapshotTotalBytes: vm.snapshot?.totalBytes"))
        for name in ["detailBody", "displayedProjection", "memoryField", "body"] {
            let source = try functionBody(named: name, in: sidebar)
            XCTAssertFalse(source.contains("lastLiveTotal ="), name)
        }
        XCTAssertFalse(sidebar.contains("selectedPid == nil"))
        XCTAssertEqual(occurrenceCount(of: "lastLiveTotal =", in: sidebar), 2)

        let events = try functionBody(
            named: "eventsForSidebar",
            in: try repoText("Pulse/Models/LastLiveTotalReducer.swift")
        )
        XCTAssertFalse(events.contains("listSelectedPid"))
        XCTAssertTrue(events.contains("return [.freeze(pid: pid, memoryBytes: memoryBytes)]"))
        XCTAssertTrue(events.contains(".newLiveSubject(pid: pid, totalBytes: snapshotTotalBytes)"))
        XCTAssertTrue(events.contains("current.showsAbsentRecord == false, previous.isNormalLive == false"))
        XCTAssertTrue(events.contains("return [live]"))
        XCTAssertFalse(events.contains(".subject(nil)"))

        let beat = try functionBody(named: "sidebarSubjectBeat", in: sidebar)
        XCTAssertTrue(beat.contains("memorySeries.isEmpty && $0.cpuSeries.isEmpty"))
        XCTAssertFalse(beat.contains("lastLiveTotal ="))
        XCTAssertFalse(body.contains("eventsForSidebar"))
    }

    func testNewModelsStayOutOfTheSamplerQuitStoreAndVMPublishedSurface() throws {
        let projection = try repoText("Pulse/Models/ResourceDetailPageProjection.swift")
        let reducer = try repoText("Pulse/Models/LastLiveTotalReducer.swift")
        XCTAssertFalse(projection.contains("LastLiveTotalReducer"))
        XCTAssertFalse(projection.contains("LastLiveTotalState"))
        XCTAssertFalse(reducer.contains("ResourceDetailPageProjection"))
        for source in [projection, reducer] {
            XCTAssertTrue(source.contains("import Foundation"))
            XCTAssertFalse(source.contains("import SwiftUI"))
            XCTAssertFalse(source.contains("import Darwin"))
            XCTAssertFalse(source.contains("import AppKit"))
            for word in [
                "HostNetworkRates", "HostDiskRates", "networkHistory", "diskHistory",
                "systemCpuPercent", "ProcessQuitOutcome", "ProcessQuitRecord", "MemorySampler",
                "@Published", "inout", "identityEvidence",
            ] {
                XCTAssertFalse(source.contains(word), word)
            }
        }
        XCTAssertTrue(projection.contains("static let processNetworkUnavailable = \"当前进程网络暂不可用\""))
        XCTAssertFalse(projection.contains("case unavailable("))

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/ResourceDetailPageProjection.swift\""))
        XCTAssertTrue(package.contains("\"Models/LastLiveTotalReducer.swift\""))
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ResourceDetailPageProjection.swift in Sources"))
        XCTAssertTrue(project.contains("path = ResourceDetailPageProjection.swift;"))
        XCTAssertTrue(project.contains("LastLiveTotalReducer.swift in Sources"))
        XCTAssertTrue(project.contains("path = LastLiveTotalReducer.swift;"))

        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        XCTAssertEqual(occurrenceCount(of: "@Published", in: vm), 26, "machine page adds machineFacts")
        for name in ["selectPage", "applySample", "applyRisingOnlySelection"] {
            let source = try functionBody(named: name, in: vm)
            XCTAssertFalse(source.contains("ResourceDetailPageProjection"), name)
            XCTAssertFalse(source.contains("LastLiveTotal"), name)
            XCTAssertFalse(source.contains("FrozenMemoryFieldSemantics"), name)
        }
        let didSet = try braceBody(after: "var selectedPid", in: vm)
        XCTAssertTrue(didSet.contains("detail = nil"))
        XCTAssertFalse(didSet.contains("ResourceDetailPageProjection"))
        XCTAssertFalse(didSet.contains("LastLiveTotal"))
        XCTAssertFalse(didSet.contains("FrozenMemoryFieldSemantics"))
        XCTAssertFalse(didSet.contains("lastLiveTotal"))

        let session = try repoText("Pulse/Models/ProcessQuitSession.swift")
        XCTAssertFalse(session.contains("totalBytes"))
        XCTAssertFalse(session.contains("FrozenMemoryFieldSemantics"))
        XCTAssertFalse(session.contains("LastLiveTotal"))
        let outcome = try repoText("Pulse/Models/ProcessQuitOutcome.swift")
        XCTAssertFalse(outcome.contains("FrozenMemoryFieldSemantics"))
        XCTAssertFalse(outcome.contains("LastLiveTotalReducer"))
        XCTAssertFalse(outcome.contains("ResourceDetailPageProjection"))
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("ResourceDetailPageProjection"))
        XCTAssertFalse(sampler.contains("LastLiveTotalReducer"))
        XCTAssertFalse(sampler.contains("FrozenMemoryFieldSemantics"))
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
        let patterns = ["func \(name)(", "func \(name)()", "private func \(name)(", "var \(name):"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw SourceReadError.missing(name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound,
              let brace = source[start...].firstIndex(of: "{")
        else { throw SourceReadError.missing(needle) }
        return try balancedSlice(from: brace, in: source, label: needle)
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw SourceReadError.missing(needle)
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
        throw SourceReadError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum SourceReadError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
