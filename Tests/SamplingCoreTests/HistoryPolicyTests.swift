import XCTest
@testable import SamplingCore

/// Literals are the retention rules from ticket #194. A missing minute is nil, never 0.
final class HistoryPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testRawTierDropsASampleOlderThanOneHour() {
        let fresh = sample(at: t0, cpu: 10)
        let stale = sample(at: t0.addingTimeInterval(-3601), cpu: 90)
        let kept = HistoryPolicy.rawSamples(from: [stale, fresh], now: t0)
        XCTAssertEqual(kept, [fresh])
    }

    func testTopProcessesKeepsTenAndDoesNotRankANilPrimaryAsZero() {
        let ranked = (0..<12).map { HistoryProcessCandidate(pid: Int32($0), name: "p\($0)", primary: Double(100 - $0)) }
        let withNil = ranked + [HistoryProcessCandidate(pid: 99, name: "missing", primary: nil)]
        let top = HistoryPolicy.topProcesses(withNil, limit: 10)
        XCTAssertEqual(top.count, 10)
        XCTAssertEqual(top.first?.pid, 0)
        XCTAssertEqual(top.last?.pid, 9)
        XCTAssertFalse(top.contains { $0.pid == 99 })
        XCTAssertFalse(top.contains { $0.pid == 10 || $0.pid == 11 })
    }

    func testPressureChangeAndSleepAreEventsNotZeroSamples() {
        let events = HistoryPolicy.events(
            previousPressure: .normal,
            pressure: .elevated,
            thermal: "serious",
            previousThermal: "nominal",
            lifecycle: .wake
        )
        XCTAssertEqual(events, [.pressure("elevated"), .thermal("serious"), .wake])
    }

    /// Literals are 7×86400 and 90×86400 before 1_700_000_000, not a second call to the same function.
    func testRetentionCutoffForSevenAndNinetyDaysIsAnExactLiteralDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            HistoryPolicy.retentionCutoff(.days(7), now: now),
            Date(timeIntervalSince1970: 1_699_395_200)
        )
        XCTAssertEqual(
            HistoryPolicy.retentionCutoff(.days(90), now: now),
            Date(timeIntervalSince1970: 1_692_224_000)
        )
        XCTAssertEqual(
            HistoryPolicy.minuteDrop(before: now, retention: .days(90)),
            Date(timeIntervalSince1970: 1_699_395_200)
        )
        XCTAssertEqual(
            HistoryPolicy.minuteDrop(before: now, retention: .days(7)),
            Date(timeIntervalSince1970: 1_699_395_200)
        )
    }

    func testMinuteBucketFloorsNinetySecondsAndNilCPUStaysNil() {
        let at = Date(timeIntervalSince1970: 90)
        XCTAssertEqual(HistoryPolicy.minuteBucketStart(at), Date(timeIntervalSince1970: 60))
        XCTAssertEqual(HistoryPolicy.quarterBucketStart(Date(timeIntervalSince1970: 1_000)), Date(timeIntervalSince1970: 900))
        let rolled = HistoryPolicy.rolled(sample(at: at, cpu: nil), step: 60)
        XCTAssertEqual(rolled.at, Date(timeIntervalSince1970: 60))
        XCTAssertNil(rolled.cpuPercent)
        XCTAssertEqual(rolled.usedBytes, 100)
        XCTAssertNil(rolled.swapUsedBytes)
        XCTAssertNotEqual(rolled.cpuPercent, 0)
    }

    func testLastSampleInAMinuteReplacesTheBucketAndAGapIsNotZero() {
        let first = HistoryPolicy.rolled(sample(at: Date(timeIntervalSince1970: 10), cpu: 8), step: 60)
        var later = sample(at: Date(timeIntervalSince1970: 50), cpu: nil)
        later.usedBytes = 40
        let last = HistoryPolicy.rolled(later, step: 60)
        XCTAssertEqual(first.at, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(last.at, first.at)
        XCTAssertNil(last.cpuPercent)
        XCTAssertEqual(last.usedBytes, 40)
        XCTAssertNotEqual(last.cpuPercent, 0)

        let afterGap = HistoryPolicy.rolled(sample(at: Date(timeIntervalSince1970: 150), cpu: 6), step: 60)
        XCTAssertEqual(afterGap.at, Date(timeIntervalSince1970: 120))
        let present = [last, afterGap]
        XCTAssertEqual(present.map(\.at), [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 120),
        ])
        XCTAssertFalse(present.contains { $0.cpuPercent == 0 })
        XCTAssertFalse(present.contains { $0.at == Date(timeIntervalSince1970: 60) })
    }

    func testAbsentRetentionKeyIsNinetyDays() {
        let name = "pulse.history.test.retention"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertEqual(HistoryRetentionPreference.defaultsKey, "pulse.historyRetentionDays")
        XCTAssertEqual(HistoryRetentionPreference.retention(in: defaults), .days(90))
        defaults.set(7, forKey: HistoryRetentionPreference.defaultsKey)
        XCTAssertEqual(HistoryRetentionPreference.retention(in: defaults), .days(7))
        defaults.set(30, forKey: HistoryRetentionPreference.defaultsKey)
        XCTAssertEqual(HistoryRetentionPreference.retention(in: defaults), .days(30))
        defaults.set(4, forKey: HistoryRetentionPreference.defaultsKey)
        XCTAssertEqual(HistoryRetentionPreference.retention(in: defaults), .days(90))
    }

    func testMissingHistoryFileIsNotZeroBytes() {
        XCTAssertEqual(HistorySettingsCopy.occupied(nil), "—")
        XCTAssertNotEqual(HistorySettingsCopy.occupied(nil), "0 字节")
        XCTAssertEqual(HistorySettingsCopy.occupied(0), "0 字节")
        XCTAssertEqual(HistorySettingsCopy.localOnly, "历史只保存在这台 Mac 上")
    }

    func testDraftKeepsRawDeletionAndUsesNinetyDaysUntilTheChoiceChanges() throws {
        var core = DashboardCore(ownPid: 1)
        XCTAssertEqual(core.historyRetention, .days(90))
        accept(&core, at: Date(timeIntervalSince1970: 1_700_000_000))
        let draft = try XCTUnwrap(core.historyDraft)
        XCTAssertEqual(draft.dropRawBefore, Date(timeIntervalSince1970: 1_700_000_000 - 3_600))
        XCTAssertEqual(draft.dropMinuteBefore, Date(timeIntervalSince1970: 1_699_395_200))
        XCTAssertEqual(draft.retentionCutoff, Date(timeIntervalSince1970: 1_692_224_000))

        core.historyRetention = .days(7)
        accept(&core, at: Date(timeIntervalSince1970: 1_700_000_000))
        let shorter = try XCTUnwrap(core.historyDraft)
        XCTAssertEqual(shorter.dropRawBefore, Date(timeIntervalSince1970: 1_700_000_000 - 3_600))
        XCTAssertEqual(shorter.dropMinuteBefore, Date(timeIntervalSince1970: 1_699_395_200))
        XCTAssertEqual(shorter.retentionCutoff, Date(timeIntervalSince1970: 1_699_395_200))
    }

    /// Unix 90 floors to minute 60 and quarter 0. Nil CPU stays nil on the rolled minute.
    func testDraftKeepsTheRawInstantAndCarriesRolledMinuteQuarterAndTopAt() throws {
        var core = DashboardCore(ownPid: 1)
        accept(&core, at: Date(timeIntervalSince1970: 90))
        let draft = try XCTUnwrap(core.historyDraft)
        XCTAssertEqual(draft.sample.at, Date(timeIntervalSince1970: 90))
        XCTAssertEqual(draft.minute.at, Date(timeIntervalSince1970: 60))
        XCTAssertNil(draft.minute.cpuPercent)
        XCTAssertNotEqual(draft.minute.cpuPercent, 0)
        XCTAssertEqual(draft.minute.usedBytes, 100)
        XCTAssertEqual(draft.quarter.at, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(draft.topAt, Date(timeIntervalSince1970: 60))
    }

    func testSettingsSectionStandsAloneAndTheStoreDoesNotKnowRetentionDays() throws {
        let history = try repoText("Pulse/Views/PulseSettingsView+History.swift")
        XCTAssertTrue(history.contains("Section(\"历史\")"))
        XCTAssertTrue(history.contains("历史只保存在这台 Mac 上"))
        XCTAssertTrue(history.contains("清空历史"))
        XCTAssertTrue(history.contains("confirmationDialog"))
        XCTAssertTrue(history.contains("HistoryPolicy.retentionCutoff"))
        XCTAssertTrue(history.contains("HistoryPolicy.minuteDrop"))
        XCTAssertFalse(history.contains("Section(\"通知\")"))
        XCTAssertFalse(history.contains("Section(\"告警规则\")"))
        XCTAssertFalse(history.contains("Section(\"登录时打开 Pulse\")"))
        XCTAssertFalse(history.contains("UserDefaults"))
        XCTAssertFalse(history.contains("时序库"))
        XCTAssertFalse(history.contains("日志"))

        let view = try WiringSourceText.text(for: "PulseSettingsView")
        XCTAssertEqual(view.components(separatedBy: "@AppStorage").count - 1, 4)
        XCTAssertTrue(view.contains("HistorySettingsSection()"))

        let store = try repoText("Pulse/Sampling/HistoryStore.swift")
        XCTAssertTrue(store.contains("func byteCount() -> UInt64?"))
        XCTAssertTrue(store.contains("func deleteAll()"))
        XCTAssertTrue(store.contains("func delete(before date: Date)"))
        XCTAssertTrue(store.contains("func samples(from "))
        XCTAssertTrue(store.contains("func minuteSamples(from "))
        XCTAssertTrue(store.contains("func events(from "))
        XCTAssertTrue(store.contains("draft.dropRawBefore"))
        XCTAssertTrue(store.contains("draft.dropMinuteBefore"))
        XCTAssertTrue(store.contains("draft.retentionCutoff"))
        XCTAssertTrue(store.contains("draft.minute"))
        XCTAssertTrue(store.contains("draft.quarter"))
        XCTAssertTrue(store.contains("draft.topAt"))
        XCTAssertTrue(store.contains("DELETE FROM top_process WHERE at = ?"))
        XCTAssertFalse(store.contains("HistoryPolicy.rolled"))
        XCTAssertEqual(store.components(separatedBy: "HistoryPolicy").count - 1, 1)
        XCTAssertTrue(store.contains("CREATE TABLE IF NOT EXISTS minute"))
        XCTAssertTrue(store.contains("CREATE TABLE IF NOT EXISTS quarter"))
        XCTAssertFalse(store.contains("HistoryRetention"))

        let noted = try repoText("Pulse/Models/DashboardCore+History.swift")
        XCTAssertTrue(noted.contains("HistoryPolicy.rolled"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(vm.contains("historyRetention = HistoryRetentionPreference.retention()"))
        XCTAssertTrue(vm.contains("sampler.sample(readChipTemperature: selectedPage == .machine, readEnergyModel: selectedPage == .cpu, readGPUEnergy: selectedPage == .gpu, readMachineRails: selectedPage == .energy)"))
        XCTAssertFalse(vm.contains("UserDefaults"))
        XCTAssertEqual(
            vm.components(separatedBy: "addObserver").count - 1,
            0
        )
    }

    private func accept(_ core: inout DashboardCore, at date: Date) {
        let frame = SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 100,
                totalBytes: 1_000,
                breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
                pressure: .normal,
                pressureMetric: 0.1,
                pressureSeries: [],
                capturedAt: date,
                swapUsedBytes: nil
            ),
            rows: [],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: nil,
            hostNetworkRates: .missing,
            hostDiskRates: .missing
        )
        _ = core.apply(result: Result<SampledFrame, ProbeError>.success(frame), accepted: true, page: .memory)
    }

    private func repoText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func sample(at date: Date, cpu: Double?) -> HistorySample {
        HistorySample(
            at: date,
            usedBytes: 100,
            pressure: .normal,
            swapUsedBytes: nil,
            cpuPercent: cpu,
            networkInBytesPerSecond: nil,
            networkOutBytesPerSecond: nil,
            diskReadBytesPerSecond: nil,
            diskWriteBytesPerSecond: nil,
            gpuPercent: nil
        )
    }
}

private enum ProbeError: Error {
    case unavailable
}
