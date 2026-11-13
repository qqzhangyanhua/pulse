import XCTest
@testable import SamplingCore

/// The draft is this tick. A missing GPU read stays nil, and a hidden thermal condition is still an event.
final class HistoryDraftTests: XCTestCase {
    func testSuccessStoresThisTickAndNotTheBusiestCore() throws {
        var core = DashboardCore(ownPid: 1)
        XCTAssertEqual(core.apply(thermalCondition: .serious), [])
        accept(&core, frame(cpu: 10, gpu: 41), page: .cpu)
        let draft = try XCTUnwrap(core.historyDraft)
        XCTAssertEqual(draft.sample.usedBytes, 100)
        XCTAssertEqual(draft.sample.pressure, .elevated)
        XCTAssertEqual(draft.sample.swapUsedBytes, 5)
        XCTAssertEqual(draft.sample.cpuPercent, 10)
        XCTAssertEqual(draft.sample.networkInBytesPerSecond, 3)
        XCTAssertEqual(draft.sample.networkOutBytesPerSecond, 4)
        XCTAssertEqual(draft.sample.diskReadBytesPerSecond, 7)
        XCTAssertEqual(draft.sample.diskWriteBytesPerSecond, 8)
        XCTAssertEqual(draft.sample.gpuPercent, 41)
        XCTAssertEqual(draft.top.map(\.pid), [7])
        XCTAssertEqual(draft.events, [.thermal("serious"), .pressure("elevated")])
        XCTAssertEqual(draft.dropRawBefore, draft.sample.at.addingTimeInterval(-3600))
        XCTAssertEqual(core.thermalNotice, ThermalNotice.throttling)
        let taken = core.consumeHistoryDraft()
        XCTAssertEqual(taken?.sample.cpuPercent, 10)
        XCTAssertNil(core.historyDraft)
    }

    func testNominalThermalIsAnEventWhileTheNoticeStaysHidden() throws {
        var core = DashboardCore(ownPid: 1)
        XCTAssertEqual(core.apply(thermalCondition: .nominal), [])
        XCTAssertNil(core.thermalNotice)
        accept(&core, frame(cpu: 10, gpu: 41))
        XCTAssertEqual(core.historyDraft?.events, [.thermal("nominal"), .pressure("elevated")])
    }

    func testARepeatedConditionDoesNotRepeatAndAMissedGPUReadStaysNil() throws {
        var core = DashboardCore(ownPid: 1)
        _ = core.apply(thermalCondition: .serious)
        accept(&core, frame(cpu: 10, gpu: 41))
        let first = try XCTUnwrap(core.historyDraft)
        _ = core.apply(thermalCondition: .serious)
        accept(&core, frame(cpu: 10, gpu: nil))
        let second = try XCTUnwrap(core.historyDraft)
        XCTAssertEqual(first.sample.gpuPercent, 41)
        XCTAssertEqual(first.events, [.thermal("serious"), .pressure("elevated")])
        XCTAssertNil(second.sample.gpuPercent)
        XCTAssertTrue(second.events.isEmpty)
        XCTAssertEqual(core.gpuPage.utilizationPercent, 41)
    }

    func testNilCPUStaysOutOfTheTopTenAndRealZeroStaysIn() throws {
        var core = DashboardCore(ownPid: 1)
        let rows = [
            row(pid: 4, cpu: nil),
            row(pid: 3, cpu: 0),
        ]
        accept(&core, frame(cpu: 10, gpu: 41, rows: rows))
        let top = try XCTUnwrap(core.historyDraft).top
        XCTAssertEqual(top.map(\.pid), [3])
        XCTAssertEqual(top.first?.primary, 0)
    }

    func testFailureAndAStaleFlightLeaveNoDraft() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, frame(cpu: 10, gpu: 41))
        XCTAssertNotNil(core.historyDraft)
        _ = core.apply(result: Result<SampledFrame, ProbeError>.failure(.unavailable), accepted: true, page: .memory)
        XCTAssertNil(core.historyDraft)
        accept(&core, frame(cpu: 10, gpu: 41), accepted: false)
        XCTAssertNil(core.historyDraft)
    }

    func testStoreStaysBehindThePolicyAndOffTheViewModelObserver() throws {
        let package = try repoText("Package.swift")
        let sources = try XCTUnwrap(package.components(separatedBy: "sources:").last)
        XCTAssertTrue(sources.contains("\"Models/HistoryPolicy.swift\""))
        XCTAssertFalse(sources.contains("HistoryStore.swift"))
        XCTAssertTrue(package.contains("\"Sampling/HistoryStore.swift\""))

        let store = try repoText("Pulse/Sampling/HistoryStore.swift")
        XCTAssertTrue(store.contains("draft.dropRawBefore"))
        XCTAssertTrue(store.contains("NSWorkspace.willSleepNotification"))
        XCTAssertTrue(store.contains("NSWorkspace.didWakeNotification"))
        XCTAssertFalse(store.contains("HistoryRetention"))
        XCTAssertFalse(store.contains("IOServiceOpen"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(vm.contains("HistoryStore.shared.write(draft)"))
        XCTAssertTrue(vm.contains("consumeHistoryDraft()"))
        XCTAssertFalse(vm.contains("historyDraft ="))
        XCTAssertEqual(occurrenceCount(of: "addObserver", in: try WiringSourceText.text(for: "MemoryDashboardVM")), 1)

        let core = try repoText("Pulse/Models/DashboardCore.swift")
        let record = try XCTUnwrap(core.range(of: "recordGPU(nodes: frame.gpuNodes"))
        let note = try XCTUnwrap(core.range(of: "noteHistory(frame)"))
        XCTAssertLessThan(record.lowerBound, note.lowerBound)
        XCTAssertFalse(core.contains("cpuHistory.record"))
    }

    private func accept(
        _ core: inout DashboardCore,
        _ frame: SampledFrame,
        accepted: Bool = true,
        page: DashboardPage = .memory
    ) {
        _ = core.apply(
            result: Result<SampledFrame, ProbeError>.success(frame),
            accepted: accepted,
            page: page
        )
    }

    private func frame(cpu: Double?, gpu: Double?, rows: [ProcessRow]? = nil) -> SampledFrame {
        let at = Date(timeIntervalSince1970: 1_700_000_100)
        let nodes: [GPUAcceleratorNode]? = gpu.map { percent in
            [GPUAcceleratorNode(statistics: [
                GPUPageProjection.deviceUtilizationKey: .number(percent),
            ])]
        }
        return SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 100,
                totalBytes: 1_000,
                breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
                pressure: .elevated,
                pressureMetric: 0.2,
                pressureSeries: [],
                capturedAt: at,
                swapUsedBytes: 5
            ),
            rows: rows ?? [row(pid: 7, cpu: 20)],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: cpu,
            hostNetworkRates: HostNetworkRates(inboundBytesPerSecond: 3, outboundBytesPerSecond: 4),
            hostDiskRates: HostDiskRates(readBytesPerSecond: 7, writeBytesPerSecond: 8),
            busiestCorePercent: 90,
            gpuNodes: nodes
        )
    }

    private func row(pid: Int32, cpu: Double?) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: "Mail",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: cpu,
            memoryBytes: 10,
            threadCount: 1
        )
    }

    private func repoText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum ProbeError: Error {
    case unavailable
}
