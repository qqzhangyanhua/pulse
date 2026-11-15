import XCTest
@testable import SamplingCore

/// Custom 告警规则. Literals are the ticket's 30-minute cooldown, one notice, and nil-is-not-zero.
final class AlertRuleSettingsTests: XCTestCase {
    func testCustomRuleSendsOnceAfterFiveMinutesThenStaysQuietWhileItStillHolds() {
        let rule = CustomAlertRule.make(
            id: "chrome-cpu",
            object: .app("Chrome"),
            metric: .cpu,
            threshold: 80,
            duration: 300,
            cooldown: 1_800,
            dailyLimit: 3
        )
        var engine = AlertRuleEngine()
        let hot = AlertFrame(processes: [
            AlertProcessSample(pid: 42, name: "Chrome", cpuPercent: 91, memoryBytes: 10),
        ])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(1_700_000_000)), [])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(1_700_000_299)), [])

        let sent = engine.evaluate(rules: [rule], frame: hot, at: at(1_700_000_300))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].id, "chrome-cpu")
        XCTAssertEqual(sent[0].body, "Chrome 的 CPU 已持续超过 80%")
        XCTAssertEqual(sent[0].page, .cpu)
        XCTAssertEqual(sent[0].pid, 42)

        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(1_700_002_100)), [])
    }

    func testCooldownBlocksTheNextEpisodeUntilThirtyMinutesAfterTheSend() {
        let rule = CustomAlertRule.make(
            id: "cpu",
            metric: .cpu,
            threshold: 80,
            duration: 0,
            cooldown: 1_800,
            dailyLimit: 5
        )
        var engine = AlertRuleEngine()
        let hot = AlertFrame(systemCpuPercent: 90)
        let cool = AlertFrame(systemCpuPercent: 10)
        let first = engine.evaluate(rules: [rule], frame: hot, at: at(1_700_000_000))
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: cool, at: at(1_700_000_010)), [])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(1_700_001_799)), [])
        let due = engine.evaluate(rules: [rule], frame: hot, at: at(1_700_001_800))
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due[0].page, .cpu)
        XCTAssertNil(due[0].pid)
    }

    func testDailyCapAllowsOneEpisodeUntilTheNextUTCDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rule = CustomAlertRule.make(
            id: "cpu",
            metric: .cpu,
            threshold: 80,
            duration: 0,
            cooldown: 0,
            dailyLimit: 1
        )
        var engine = AlertRuleEngine()
        let day = TimeInterval(1_704_067_200)
        let hot = AlertFrame(systemCpuPercent: 88)
        let cool = AlertFrame(systemCpuPercent: 1)
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(day), calendar: calendar).count, 1)
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: cool, at: at(day + 10), calendar: calendar), [])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(day + 20), calendar: calendar), [])
        let next = engine.evaluate(rules: [rule], frame: hot, at: at(day + 86_400), calendar: calendar)
        XCTAssertEqual(next.count, 1)
    }

    func testNilChipTemperatureDoesNotFireAndZeroDoesNotCountAsHot() {
        let rule = CustomAlertRule.make(
            id: "hot",
            metric: .chipTemperature,
            threshold: 90,
            duration: 0,
            cooldown: 1_800,
            dailyLimit: 3
        )
        var engine = AlertRuleEngine()
        let moment = at(1_700_000_000)
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: AlertFrame(chipTemperatureCelsius: nil), at: moment), [])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: AlertFrame(chipTemperatureCelsius: 0), at: moment), [])
        let sent = engine.evaluate(rules: [rule], frame: AlertFrame(chipTemperatureCelsius: 91), at: moment)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].body, "整机芯片温度已持续超过 90 °C")
        XCTAssertEqual(sent[0].page, .machine)
        XCTAssertNil(sent[0].pid)
    }

    func testNilGapDoesNotFinishOrResetAPendingChipRule() {
        let rule = CustomAlertRule.make(
            id: "hot",
            metric: .chipTemperature,
            threshold: 90,
            duration: 300,
            cooldown: 0,
            dailyLimit: 3
        )
        var engine = AlertRuleEngine()
        let hot = AlertFrame(chipTemperatureCelsius: 95)
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: hot, at: at(1_700_000_000)), [])
        XCTAssertEqual(
            engine.evaluate(rules: [rule], frame: AlertFrame(chipTemperatureCelsius: nil), at: at(1_700_000_300)),
            []
        )
        let sent = engine.evaluate(rules: [rule], frame: hot, at: at(1_700_000_300))
        XCTAssertEqual(sent.count, 1)
    }

    func testNilDiskFreeDoesNotFireAndARealEmptyDiskDoes() {
        let rule = CustomAlertRule.make(
            id: "disk",
            metric: .diskFree,
            threshold: 10_737_418_240,
            duration: 0,
            cooldown: 1_800,
            dailyLimit: 3
        )
        var engine = AlertRuleEngine()
        let moment = at(1_700_000_000)
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: AlertFrame(diskFreeBytes: nil), at: moment), [])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: AlertFrame(diskFreeBytes: 10_737_418_240), at: moment), [])
        let empty = engine.evaluate(rules: [rule], frame: AlertFrame(diskFreeBytes: 0), at: moment)
        XCTAssertEqual(empty.count, 1)
        XCTAssertEqual(empty[0].body, "整机磁盘剩余已持续低于 10 GB")
        XCTAssertEqual(empty[0].page, .machine)
        XCTAssertNil(empty[0].pid)
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: AlertFrame(diskFreeBytes: 10_737_418_239), at: at(1_700_000_001)), [])

        var justUnder = AlertRuleEngine()
        XCTAssertEqual(
            justUnder.evaluate(rules: [rule], frame: AlertFrame(diskFreeBytes: 10_737_418_239), at: moment).count,
            1
        )
    }

    func testEightyPercentDoesNotFireAndAMissingAppIsNotZero() {
        let rule = CustomAlertRule.make(
            id: "chrome",
            object: .app("Chrome"),
            metric: .cpu,
            threshold: 80,
            duration: 0
        )
        var engine = AlertRuleEngine()
        let exact = AlertFrame(processes: [
            AlertProcessSample(pid: 1, name: "Chrome", cpuPercent: 80, memoryBytes: 1),
        ])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: exact, at: at(1_700_000_000)), [])
        let other = AlertFrame(processes: [
            AlertProcessSample(pid: 2, name: "Mail", cpuPercent: 99, memoryBytes: 1),
        ])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: other, at: at(1_700_000_001)), [])
        let over = AlertFrame(processes: [
            AlertProcessSample(pid: 7, name: "Chrome", cpuPercent: 80.1, memoryBytes: 1),
        ])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: over, at: at(1_700_000_002)).map(\.pid), [7])
    }

    func testMatchingAppUsesTheHighestCPUAndTheLowerPid() {
        let rule = CustomAlertRule.make(
            id: "chrome",
            object: .app("Chrome"),
            metric: .cpu,
            threshold: 80,
            duration: 0
        )
        let frame = AlertFrame(processes: [
            AlertProcessSample(pid: 8, name: "Chrome", cpuPercent: 90, memoryBytes: 1),
            AlertProcessSample(pid: 3, name: "Chrome", cpuPercent: 90, memoryBytes: 1),
            AlertProcessSample(pid: 1, name: "Chrome", cpuPercent: nil, memoryBytes: 9_000),
        ])
        var engine = AlertRuleEngine()
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: frame, at: at(1_700_000_000)).map(\.pid), [3])
    }

    func testMachineCPUDoesNotBorrowAProcessReading() {
        let rule = CustomAlertRule.make(id: "machine", metric: .cpu, threshold: 80, duration: 0)
        let frame = AlertFrame(
            systemCpuPercent: nil,
            processes: [AlertProcessSample(pid: 4, name: "Chrome", cpuPercent: 99, memoryBytes: 1)]
        )
        var engine = AlertRuleEngine()
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: frame, at: at(1_700_000_000)), [])
    }

    func testMachineCPUSelectsTheBusiestProcess() {
        let rule = CustomAlertRule.make(id: "machine", metric: .cpu, threshold: 80, duration: 0)
        let frame = AlertFrame(
            systemCpuPercent: 92,
            processes: [
                AlertProcessSample(pid: 2, name: "Mail", cpuPercent: 10, memoryBytes: 1),
                AlertProcessSample(pid: 9, name: "Chrome", cpuPercent: 40, memoryBytes: 1),
                AlertProcessSample(pid: 1, name: "helper", cpuPercent: nil, memoryBytes: 1),
            ]
        )
        var engine = AlertRuleEngine()
        let sent = engine.evaluate(rules: [rule], frame: frame, at: at(1_700_000_000))
        XCTAssertEqual(sent.map(\.pid), [9])
        XCTAssertEqual(sent.first?.body, "整机 CPU 已持续超过 80%")
    }

    func testMemoryPressureSelectsTheHeaviestProcessAndNormalDoesNotFire() {
        let rule = CustomAlertRule.make(id: "pressure", metric: .memoryPressure, threshold: 0, duration: 0)
        let processes = [
            AlertProcessSample(pid: 2, name: "Mail", cpuPercent: 1, memoryBytes: 100),
            AlertProcessSample(pid: 5, name: "Chrome", cpuPercent: 1, memoryBytes: 500),
        ]
        var engine = AlertRuleEngine()
        XCTAssertEqual(
            engine.evaluate(rules: [rule], frame: AlertFrame(memoryPressure: .normal, processes: processes), at: at(1_700_000_000)),
            []
        )
        XCTAssertEqual(
            engine.evaluate(rules: [rule], frame: AlertFrame(memoryPressure: nil, processes: processes), at: at(1_700_000_001)),
            []
        )
        let sent = engine.evaluate(
            rules: [rule],
            frame: AlertFrame(memoryPressure: .elevated, processes: processes),
            at: at(1_700_000_002)
        )
        XCTAssertEqual(sent.map(\.page), [.memory])
        XCTAssertEqual(sent.map(\.pid), [5])
        XCTAssertEqual(sent.first?.body, "整机内存压力已持续偏高")
    }

    func testAppMemoryFootprintNamesTheHeavierProcess() {
        let rule = CustomAlertRule.make(
            id: "chrome-mem",
            object: .app("Chrome"),
            metric: .memoryFootprint,
            threshold: 8_589_934_592,
            duration: 0
        )
        let frame = AlertFrame(processes: [
            AlertProcessSample(pid: 4, name: "Chrome", cpuPercent: 1, memoryBytes: 1_000),
            AlertProcessSample(pid: 6, name: "Chrome", cpuPercent: 1, memoryBytes: 9_000_000_000),
            AlertProcessSample(pid: 8, name: "Chrome", cpuPercent: 1, memoryBytes: nil),
        ])
        var engine = AlertRuleEngine()
        let sent = engine.evaluate(rules: [rule], frame: frame, at: at(1_700_000_000))
        XCTAssertEqual(sent.map(\.pid), [6])
        XCTAssertEqual(sent.first?.body, "Chrome 的内存占用已持续超过 8 GB")
        XCTAssertEqual(sent.first?.page, .memory)
    }

    func testDisabledRuleDoesNotSend() {
        let rule = CustomAlertRule.make(
            id: "chrome",
            enabled: false,
            object: .app("Chrome"),
            metric: .cpu,
            threshold: 80,
            duration: 0
        )
        var engine = AlertRuleEngine()
        let frame = AlertFrame(processes: [
            AlertProcessSample(pid: 1, name: "Chrome", cpuPercent: 99, memoryBytes: 1),
        ])
        XCTAssertEqual(engine.evaluate(rules: [rule], frame: frame, at: at(1_700_000_000)), [])
    }

    func testCustomRulesCanBeAddedEditedDisabledAndDeletedButBuiltinCannot() {
        let chrome = CustomAlertRule.make(
            id: "chrome",
            object: .app("Chrome"),
            metric: .cpu,
            threshold: 80,
            duration: 300
        )
        var catalog = AlertRuleCatalog.empty.adding(chrome)
        XCTAssertEqual(catalog.custom, [chrome])

        var edited = chrome
        edited.threshold = 70
        catalog = catalog.replacing(edited)
        XCTAssertEqual(catalog.custom.map(\.threshold), [70])

        catalog = catalog.settingEnabled(id: "chrome", enabled: false)
        XCTAssertEqual(catalog.custom.map(\.enabled), [false])

        catalog = catalog.removing(id: AlertRule.memoryPressure.id)
        XCTAssertEqual(catalog.custom.map(\.id), ["chrome"])
        catalog = catalog.settingEnabled(id: AlertRule.memoryPressure.id, enabled: false)
        XCTAssertEqual(catalog.custom.map(\.enabled), [false])

        catalog = catalog.removing(id: "chrome")
        XCTAssertEqual(catalog.custom, [])
        XCTAssertEqual(catalog.removing(id: "missing").custom, [])

        let builtin = CustomAlertRule.make(id: "pulse.pressureNotice", metric: .memoryPressure, threshold: 0)
        XCTAssertFalse(builtin.isValid)
        XCTAssertEqual(AlertRuleCatalog.empty.adding(builtin).custom, [])

        let padded = CustomAlertRule.make(id: "pad", object: .app(" Chrome"), metric: .cpu, threshold: 80)
        XCTAssertEqual(AlertRuleCatalog.empty.adding(padded).custom, [])
    }

    func testAppRulesCannotUseMachineOnlyMetrics() {
        for metric in [AlertMetric.memoryPressure, .chipTemperature, .diskFree, .gpuUtilization] {
            let rule = CustomAlertRule.make(id: "bad-\(metric.rawValue)", object: .app("Chrome"), metric: metric, threshold: 1)
            XCTAssertEqual(AlertRuleCatalog.empty.adding(rule).custom, [], metric.rawValue)
        }
    }

    func testDefaultsAreThirtyMinutesAndThreeADayWhileBuiltinStaysFiveMinutes() {
        XCTAssertEqual(CustomAlertRule.defaultCooldown, 1_800)
        XCTAssertEqual(CustomAlertRule.defaultDailyLimit, 3)
        XCTAssertEqual(CustomAlertRule.defaultDuration, 300)
        let made = CustomAlertRule.make(id: "n")
        XCTAssertEqual(made.cooldown, 1_800)
        XCTAssertEqual(made.dailyLimit, 3)
        XCTAssertEqual(made.duration, 300)
        XCTAssertEqual(made.listDetail, "持续 5 分钟 · 冷却 30 分钟 · 每日 3 次")
        XCTAssertEqual(AlertRule.memoryPressure.rearm, 300)
        XCTAssertEqual(AlertRule.memoryPressure.cooldown, 0)
        XCTAssertNil(AlertRule.memoryPressure.dailyLimit)
        XCTAssertEqual(AlertRule.memoryPressure.id, "pulse.pressureNotice")
        XCTAssertTrue(AlertRule.memoryPressure.builtin)
    }

    func testCopyUsesTheGlossaryWord() {
        XCTAssertEqual(AlertRuleCopy.sectionTitle, "告警规则")
        XCTAssertEqual(AlertRuleCopy.addButton, "添加告警规则")
        XCTAssertFalse(AlertRuleCopy.sectionTitle.contains("警报"))
        XCTAssertFalse(AlertRuleCopy.addButton.contains("警报"))
        XCTAssertFalse(AlertRuleCopy.builtinNote.contains("警报"))
        let body = CustomAlertRule.make(id: "c", object: .app("Chrome"), metric: .cpu, threshold: 80).notificationBody
        XCTAssertEqual(body, "Chrome 的 CPU 已持续超过 80%")
        XCTAssertFalse(body.contains("警报"))
    }

    func testThresholdDisplayStoresGigabytesAsBytes() {
        XCTAssertEqual(AlertMetric.memoryFootprint.storedThreshold(displayText: "8"), 8_589_934_592)
        XCTAssertEqual(AlertMetric.diskFree.storedThreshold(displayText: "10"), 10_737_418_240)
        XCTAssertEqual(AlertMetric.cpu.storedThreshold(displayText: "80"), 80)
        XCTAssertEqual(AlertMetric.chipTemperature.storedThreshold(displayText: "90"), 90)
        XCTAssertEqual(AlertMetric.memoryPressure.storedThreshold(displayText: ""), 0)
        XCTAssertNil(AlertMetric.cpu.storedThreshold(displayText: ""))
        XCTAssertNil(AlertMetric.cpu.storedThreshold(displayText: "-1"))
        XCTAssertEqual(AlertMetric.memoryFootprint.displayThreshold(8_589_934_592), "8")
    }

    func testStoredRulesRoundTripAndDropTheBuiltinId() {
        let rule = CustomAlertRule.make(id: "ok", object: .app("Chrome"), metric: .cpu, threshold: 80, duration: 300)
        let stored = AlertRuleStore.stored(AlertRuleCatalog(custom: [rule]))
        XCTAssertEqual(AlertRuleStore.catalog(stored: stored).custom, [rule])
        XCTAssertEqual(AlertRuleStore.catalog(stored: "").custom, [])
        XCTAssertEqual(AlertRuleStore.catalog(stored: "{]").custom, [])
        XCTAssertEqual(AlertRuleStore.catalog(stored: "[]").custom, [])

        let builtin = CustomAlertRule.make(id: "pulse.pressureNotice", metric: .memoryPressure, threshold: 0)
        let data = try! JSONEncoder().encode([builtin, rule])
        let text = String(data: data, encoding: .utf8)!
        XCTAssertEqual(AlertRuleStore.catalog(stored: text).custom, [rule])
        XCTAssertEqual(AlertRuleStore.defaultsKey, "pulse.alertRules")
    }

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
        XCTAssertEqual(core.gpuAlertUtilizationPercent, 90)
        XCTAssertEqual(core.gpuPage.utilizationPercent, 90)

        _ = core.apply(
            result: Result<SampledFrame, AlertGPUDeliveryError>.success(
                gpuFrame(nodes: nil, at: 1_700_000_002)
            ),
            accepted: true,
            page: .cpu
        )
        XCTAssertEqual(core.gpuPage.utilizationPercent, 90)
        XCTAssertNil(core.gpuAlertUtilizationPercent)

        let frame = AlertFrame.sampled(
            systemCpuPercent: core.systemCpuPercent,
            usedMemoryBytes: core.snapshot?.usedBytes,
            memoryPressure: core.snapshot?.pressure,
            chipCelsius: nil,
            diskFreeBytes: nil,
            gpuUtilizationPercent: core.gpuAlertUtilizationPercent,
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
        XCTAssertTrue(center.contains("gpuUtilizationPercent: dashboard.gpuAlertUtilizationPercent"))
        XCTAssertFalse(center.contains("GPU 使用率"))
    }

    func testClickRouteDecodesThePageAndPid() {
        XCTAssertEqual(AlertNoticeRoute.pageKey, "pulse.alert.page")
        XCTAssertEqual(AlertNoticeRoute.pidKey, "pulse.alert.pid")
        XCTAssertEqual(AlertNoticeRoute.decode(page: "cpu", pid: "42"), AlertNoticeRoute(page: .cpu, pid: 42))
        XCTAssertEqual(AlertNoticeRoute.decode(page: "machine", pid: nil), AlertNoticeRoute(page: .machine, pid: nil))
        XCTAssertEqual(AlertNoticeRoute.decode(page: "memory", pid: ""), AlertNoticeRoute(page: .memory, pid: nil))
        XCTAssertNil(AlertNoticeRoute.decode(page: "nope", pid: nil))
        XCTAssertNil(AlertNoticeRoute.decode(page: "cpu", pid: "no"))
        XCTAssertNil(AlertNoticeRoute.decode(page: nil, pid: "1"))
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
