import XCTest
@testable import SamplingCore

final class SymptomDiagnosisTests: XCTestCase {
    func testSlowRanksPressureAndABusyProcessAndSkipsNilCPU() {
        let finding = SymptomDiagnosis.finding(.slow, input: SymptomInput(
            processes: [
                SymptomProcess(pid: 4, name: "Idle", cpuPercent: nil, energyWatts: nil),
                SymptomProcess(pid: 9, name: "Build", cpuPercent: 0, energyWatts: nil),
                SymptomProcess(pid: 12, name: "Encode", cpuPercent: 91, energyWatts: nil)
            ],
            memoryPressure: .elevated
        ))
        XCTAssertEqual(finding.causes.map(\.title), ["内存压力偏高", "Encode"])
        XCTAssertEqual(finding.causes[1].pid, 12)
        XCTAssertEqual(finding.causes[1].page, .cpu)
        XCTAssertFalse(finding.causes.contains { $0.title == "Idle" })
        XCTAssertFalse(finding.causes.contains { $0.title == "Build" })
    }

    func testHotUsesThermalCPUAndGPU() {
        let finding = SymptomDiagnosis.finding(.hot, input: SymptomInput(
            systemCpuPercent: 90,
            thermalName: "critical",
            gpuPercent: 88
        ))
        XCTAssertEqual(finding.causes.map(\.page), [.machine, .cpu, .gpu])
        XCTAssertTrue(finding.causes[0].evidence.contains("critical"))
    }

    func testFanSaysRPMIsUnreadableAndDoesNotReadSMC() throws {
        let finding = SymptomDiagnosis.finding(.fan, input: SymptomInput(
            systemCpuPercent: 90,
            thermalName: "nominal",
            gpuPercent: nil
        ))
        XCTAssertEqual(finding.note, "读不到风扇转速")
        XCTAssertEqual(finding.causes.map(\.title), ["整机 CPU 偏高"])
        let source = try repoText("Pulse/Models/SymptomDiagnosis.swift")
        XCTAssertFalse(source.contains("SMC"))
        XCTAssertFalse(source.contains("IOServiceOpen"))
    }

    func testFastDischargeNamesTheProcessAndIgnoresNilWatts() {
        let finding = SymptomDiagnosis.finding(.battery, input: SymptomInput(
            processes: [
                SymptomProcess(pid: 3, name: "Missing", cpuPercent: nil, energyWatts: nil),
                SymptomProcess(pid: 8, name: "Player", cpuPercent: 10, energyWatts: 12.5)
            ],
            dischargeMilliamps: -2_000
        ))
        XCTAssertEqual(finding.causes.map(\.title), ["电池正在较快放电", "Player"])
        XCTAssertEqual(finding.causes[1].page, .energy)
        XCTAssertEqual(finding.causes[1].pid, 8)
    }

    func testDiskFullSaysPurgeableIsMissingAndDoesNotUseZero() {
        let finding = SymptomDiagnosis.finding(.disk, input: SymptomInput(
            diskFreeBytes: 1_000,
            diskTotalBytes: 100_000,
            purgeableBytes: nil
        ))
        XCTAssertEqual(finding.causes.count, 1)
        XCTAssertTrue(finding.causes[0].evidence.contains("可清除空间读不到"))
        XCTAssertFalse(finding.causes[0].evidence.contains("可清除 0"))
        XCTAssertEqual(finding.causes[0].page, .machine)
    }

    func testDiskWithRoomIsUnknown() {
        let finding = SymptomDiagnosis.finding(.disk, input: SymptomInput(
            diskFreeBytes: 80,
            diskTotalBytes: 100,
            purgeableBytes: nil
        ))
        XCTAssertEqual(finding.headline, "看不出原因")
        XCTAssertTrue(finding.causes.isEmpty)
    }

    func testSleepHoldersAreCauses() {
        let finding = SymptomDiagnosis.finding(.sleep, input: SymptomInput(
            sleep: .held([
                SymptomHeldSleep(pid: 40, name: "caffeinate", typeText: "防止显示器睡眠")
            ])
        ))
        XCTAssertEqual(finding.causes.count, 1)
        XCTAssertEqual(finding.causes[0].pid, 40)
        XCTAssertEqual(finding.causes[0].page, .energy)
    }

    func testUnreadSleepDoesNotClaimNobodyIsBlocking() {
        let finding = SymptomDiagnosis.finding(.sleep, input: SymptomInput(sleep: .unread))
        XCTAssertEqual(finding.headline, "看不出原因")
        XCTAssertNil(finding.note)
        XCTAssertFalse((finding.note ?? "").contains("没有进程在阻止睡眠"))
    }

    func testQuietMachineSaysItCannotTell() {
        let finding = SymptomDiagnosis.finding(.slow, input: SymptomInput())
        XCTAssertEqual(finding.headline, SymptomFinding.unknown)
        XCTAssertTrue(finding.causes.isEmpty)
    }

    func testRecentCPUGapsAreNotAveragedAsZero() {
        let finding = SymptomDiagnosis.finding(.slow, input: SymptomInput(
            recentCPU: [nil, nil, 10, nil]
        ))
        XCTAssertTrue(finding.causes.isEmpty)
    }

    func testDiagnosisButtonStaysOutsideTheFilterGroup() throws {
        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        XCTAssertTrue(dashboard.contains("诊断"))
        let group = try braceBody(after: "ToolbarItemGroup(placement: .primaryAction)", in: dashboard)
        XCTAssertFalse(group.contains("诊断"))
        XCTAssertFalse(group.contains("保存当前快照"))
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/SymptomDiagnosis.swift\""))
        XCTAssertFalse(package.contains("SymptomPanel.swift"))
    }

    private func repoText(_ relative: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return try String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle) else {
            XCTFail("missing \(needle)")
            return ""
        }
        guard let open = source[start.upperBound...].firstIndex(of: "{") else {
            XCTFail("missing brace")
            return ""
        }
        var depth = 0
        var index = open
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[open...index])
                }
            }
            index = source.index(after: index)
        }
        XCTFail("unbalanced")
        return ""
    }
}
