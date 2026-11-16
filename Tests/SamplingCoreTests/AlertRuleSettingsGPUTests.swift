import XCTest
@testable import SamplingCore

/// GPU utilization alert rules. A missing reading is not zero, and the notice opens the GPU page.
final class AlertRuleSettingsGPUTests: XCTestCase {
    func testGPURuleFiresFromTheSelectedAcceleratorAndOpensTheGPUPage() {
        let rule = CustomAlertRule.make(
            id: "gpu",
            metric: .gpuUtilization,
            threshold: 85,
            duration: 0
        )
        let frame = AlertFrame.sampled(
            systemCpuPercent: 1,
            usedMemoryBytes: 1,
            memoryPressure: .normal,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [
                accelerator(memory: 100, utilization: 10),
                accelerator(memory: 800, utilization: 90),
            ],
            processes: [
                AlertProcessSample(pid: 4, name: "Chrome", cpuPercent: 99, memoryBytes: 9_000),
            ]
        )
        var engine = AlertRuleEngine()
        let sent = engine.evaluate(rules: [rule], frame: frame, at: at(1_700_000_000))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].body, "整机 GPU 使用率已持续超过 85%")
        XCTAssertEqual(sent[0].page, .gpu)
        XCTAssertNil(sent[0].pid)
        XCTAssertEqual(frame.gpuUtilizationPercent, 90)
    }

    func testGPURuleDoesNotBorrowAnotherAcceleratorOrTreatMissingAsZero() {
        let rule = CustomAlertRule.make(id: "gpu", metric: .gpuUtilization, threshold: 85, duration: 300)
        var quiet = AlertRuleEngine()
        let borrowed = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [
                accelerator(memory: 800, utilization: 10),
                accelerator(memory: 100, utilization: 99),
            ],
            processes: []
        )
        XCTAssertEqual(borrowed.gpuUtilizationPercent, 10)
        XCTAssertEqual(quiet.evaluate(rules: [rule], frame: borrowed, at: at(1_700_000_000)), [])

        var pending = AlertRuleEngine()
        let hot = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [accelerator(memory: 800, utilization: 90)],
            processes: []
        )
        XCTAssertEqual(pending.evaluate(rules: [rule], frame: hot, at: at(1_700_000_000)), [])
        let missing = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [
                GPUAcceleratorNode(statistics: [
                    "In use system memory": .bytes(80),
                    "Renderer Utilization %": .number(70),
                ]),
                accelerator(memory: 10, utilization: 99),
            ],
            processes: []
        )
        XCTAssertNil(missing.gpuUtilizationPercent)
        XCTAssertEqual(pending.evaluate(rules: [rule], frame: missing, at: at(1_700_000_300)), [])
        let sent = pending.evaluate(rules: [rule], frame: hot, at: at(1_700_000_300))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].body, "整机 GPU 使用率已持续超过 85%")
        XCTAssertEqual(sent[0].page, .gpu)

        let exact = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [accelerator(memory: 1, utilization: 85)],
            processes: []
        )
        var exactEngine = AlertRuleEngine()
        XCTAssertEqual(exactEngine.evaluate(rules: [rule], frame: exact, at: at(1_700_000_000)), [])

        let unread = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: nil,
            processes: []
        )
        XCTAssertNil(unread.gpuUtilizationPercent)
    }

    func testRealZeroGPUUtilizationClearsAPendingRule() {
        let rule = CustomAlertRule.make(id: "gpu", metric: .gpuUtilization, threshold: 85, duration: 300)
        var engine = AlertRuleEngine()
        let hot = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [accelerator(memory: 0, utilization: 90)],
            processes: []
        )
        let idle = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [accelerator(memory: 0, utilization: 0)],
            processes: []
        )
        XCTAssertEqual(idle.gpuUtilizationPercent, 0)
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(1_700_000_000)), [])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: idle, at: at(1_700_000_300)), [])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(1_700_000_300)), [])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(1_700_000_600)).count, 1)
    }

    func testAppGPURuleIsRejectedAndDoesNotFire() {
        let rule = CustomAlertRule.make(
            id: "chrome-gpu",
            object: .app("Chrome"),
            metric: .gpuUtilization,
            threshold: 85,
            duration: 0
        )
        XCTAssertFalse(rule.isValid)
        XCTAssertEqual(AlertRuleCatalog.empty.adding(rule).custom, [])
        let frame = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [accelerator(memory: 800, utilization: 99)],
            processes: [AlertProcessSample(pid: 4, name: "Chrome", cpuPercent: 99, memoryBytes: 9_000)]
        )
        var engine = AlertRuleEngine()
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: frame, at: at(1_700_000_000)), [])
    }

    func testChoosingGPUUtilizationDefaultsTheThresholdToEightyFive() {
        XCTAssertEqual(AlertMetric.gpuUtilization.title, "GPU 使用率")
        XCTAssertEqual(AlertMetric.gpuUtilization.thresholdUnit, "%")
        XCTAssertEqual(AlertMetric.gpuUtilization.page, .gpu)
        XCTAssertEqual(AlertMetric.gpuUtilization.defaultThreshold, 85)
        XCTAssertEqual(AlertMetric.gpuUtilization.storedThreshold(displayText: "85"), 85)
        XCTAssertEqual(AlertMetric.gpuUtilization.displayThreshold(85), "85")
        XCTAssertEqual(AlertMetricForm.thresholdText(afterChoosing: .gpuUtilization, current: "80"), "85")
        XCTAssertEqual(AlertMetricForm.thresholdText(afterChoosing: .cpu, current: "70"), "70")
        XCTAssertEqual(CustomAlertRule.defaultDuration, 300)
        XCTAssertEqual(CustomAlertRule.make(id: "gpu", metric: .gpuUtilization, threshold: 85).duration, 300)
        XCTAssertTrue(AlertMetric.allCases.map(\.title).contains("GPU 使用率"))
    }

    func testSelectedNodeIOReportPercentIsTheGPUAlertReading() {
        let rule = CustomAlertRule.make(id: "gpu", metric: .gpuUtilization, threshold: 85, duration: 0)
        let fallback = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [
                GPUAcceleratorNode(
                    statistics: ["In use system memory": .bytes(80)],
                    ioReportDevicePercent: 92
                ),
                accelerator(memory: 10, utilization: 44),
            ],
            processes: []
        )
        XCTAssertEqual(fallback.gpuUtilizationPercent, 92)
        var engine = AlertRuleEngine()
        let sent = engine.evaluate(rules: [rule], frame: fallback, at: at(1_700_000_000))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].page, .gpu)

        let blocked = AlertFrame.sampled(
            systemCpuPercent: nil,
            usedMemoryBytes: nil,
            memoryPressure: nil,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuNodes: [
                GPUAcceleratorNode(
                    statistics: [
                        "In use system memory": .bytes(80),
                        "Device Utilization %": .number(150),
                    ],
                    ioReportDevicePercent: 92
                ),
                accelerator(memory: 10, utilization: 99),
            ],
            processes: []
        )
        XCTAssertNil(blocked.gpuUtilizationPercent)
        var blockedEngine = AlertRuleEngine()
        XCTAssertEqual(blockedEngine.evaluate(rules: [rule], frame: blocked, at: at(1_700_000_000)), [])
    }

    func testAlertFrameDropsAGPUPagePercentWhenThisTickDidNotRead() throws {
        var core = DashboardCore(ownPid: 1)
        _ = core.apply(
            result: Result<SampledFrame, AlertGPUDeliveryError>.success(
                gpuFrame(nodes: [accelerator(memory: 800, utilization: 90)], at: 1_700_000_000)
            ),
            accepted: true,
            page: .memory
        )
        XCTAssertEqual(core.gpu.alertUtilizationPercent, 90)
        XCTAssertEqual(core.gpu.page.utilizationPercent, 90)

        _ = core.apply(
            result: Result<SampledFrame, AlertGPUDeliveryError>.success(
                gpuFrame(nodes: nil, at: 1_700_000_002)
            ),
            accepted: true,
            page: .cpu
        )
        XCTAssertEqual(core.gpu.page.utilizationPercent, 90)
        XCTAssertNil(core.gpu.alertUtilizationPercent)

        let frame = AlertFrame.sampled(
            systemCpuPercent: core.systemCpuPercent,
            usedMemoryBytes: core.snapshot?.usedBytes,
            memoryPressure: core.snapshot?.pressure,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuUtilizationPercent: core.gpu.alertUtilizationPercent,
            processes: []
        )
        XCTAssertNil(frame.gpuUtilizationPercent)
    }

    func testSettingsPickerOffersGPUUtilizationAndFillsEightyFive() throws {
        let editor = try String(
            contentsOf: repoRoot().appendingPathComponent("Pulse/Views/PulseSettingsView+AlertRules.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(editor.contains("objectIsApp ? [.cpu, .memoryFootprint] : Array(AlertMetric.allCases)"))
        XCTAssertTrue(editor.contains("Text(metric.title)"))
        XCTAssertTrue(editor.contains("AlertMetricForm.thresholdText"))
        let metricChange = try slice(from: ".onChange(of: model.metric)", until: ".onChange(of: model.objectIsApp)", in: editor)
        XCTAssertFalse(metricChange.contains("durationMinutes"))
        XCTAssertEqual(AlertNoticeRoute.decode(page: "gpu", pid: nil), AlertNoticeRoute(page: .gpu, pid: nil))

        let center = try String(
            contentsOf: repoRoot().appendingPathComponent("Pulse/MenuBar/PressureNoticeCenter.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(center.contains("gpuUtilizationPercent: dashboard.gpu.alertUtilizationPercent"))
        XCTAssertFalse(center.contains("GPU 使用率"))
    }
    private func at(_ time: TimeInterval) -> Date {
        Date(timeIntervalSince1970: time)
    }

    private func accelerator(memory: UInt64, utilization: Double) -> GPUAcceleratorNode {
        GPUAcceleratorNode(statistics: [
            "In use system memory": .bytes(memory),
            "Device Utilization %": .number(utilization),
        ])
    }

    private func gpuFrame(nodes: [GPUAcceleratorNode]?, at time: TimeInterval) -> SampledFrame {
        let capturedAt = Date(timeIntervalSince1970: time)
        return SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 1,
                totalBytes: 2,
                breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 0, compressedBytes: 0, cachedBytes: 0),
                pressure: .normal,
                pressureMetric: 0,
                pressureSeries: [],
                capturedAt: capturedAt
            ),
            rows: [],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: nil,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            gpuNodes: nodes
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func slice(from start: String, until end: String, in source: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
        else { throw AlertRuleSettingsSourceError.missing(start) }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}

private enum AlertGPUDeliveryError: Error {
    case unused
}

private enum AlertRuleSettingsSourceError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
