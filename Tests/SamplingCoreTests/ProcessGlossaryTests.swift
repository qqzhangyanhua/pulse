import XCTest
@testable import SamplingCore

final class ProcessGlossaryTests: XCTestCase {
    func testKnownNamesReturnOneCalmSentence() {
        XCTAssertGreaterThanOrEqual(ProcessGlossary.notes.count, 30)
        XCTAssertEqual(ProcessGlossary.note(for: "WindowServer"), "把窗口画到屏幕上。")
        XCTAssertEqual(ProcessGlossary.note(for: " kernel_task "), ProcessGlossary.notes["kernel_task"])
        XCTAssertNil(ProcessGlossary.note(for: "Chrome"))
        XCTAssertNil(ProcessGlossary.note(for: "   "))
        XCTAssertNil(ProcessGlossary.note(for: ""))
        XCTAssertFalse(ProcessGlossary.notes.values.contains("未知"))
    }

    func testWindowServerReturnsQuitSafetyUnderTheSameSentence() {
        let entry = ProcessGlossary.entry(for: "WindowServer")
        XCTAssertEqual(entry?.note, "把窗口画到屏幕上。")
        XCTAssertEqual(entry?.quitSafety, .systemProcess)
        XCTAssertEqual(
            entry?.quitSafetyText,
            "不建议退出（系统进程）。结束后，当前登录会话里的窗口会一起消失。"
        )
        XCTAssertEqual(ProcessGlossary.note(for: " WindowServer "), entry?.note)
        XCTAssertNil(ProcessGlossary.entry(for: "windowserver"))
        XCTAssertNil(ProcessGlossary.entry(for: "Chrome"))
        XCTAssertNil(ProcessGlossary.entry(for: "   "))
        XCTAssertNil(ProcessGlossary.entry(for: ""))
    }

    func testEveryExistingNameHasAQuitSafetyJudgmentAndReason() {
        let system = ProcessQuitSafety.systemProcess
        let restarts = ProcessQuitSafety.restarts
        let expected: [String: (ProcessQuitSafety, String)] = [
            "kernel_task": (system, "内核用来调度 CPU 的进程。"),
            "WindowServer": (system, "把窗口画到屏幕上。"),
            "loginwindow": (system, "负责登录和注销。"),
            "launchd": (system, "按系统安排启动其他进程。"),
            "runningboardd": (system, "管理 App 是否还在运行。"),
            "powerd": (system, "管理睡眠和电源。"),
            "configd": (system, "管理系统和网络配置。"),
            "logd": (system, "收集系统日志。"),
            "cfprefsd": (system, "读取和保存偏好设置。"),
            "tccd": (system, "记住隐私权限的选择。"),
            "trustd": (system, "检查证书。"),
            "syspolicyd": (system, "检查 App 能否打开。"),
            "fseventsd": (system, "观察文件有没有变化。"),
            "notifyd": (system, "在进程之间传递系统通知。"),
            "distnoted": (system, "在进程之间传递通知。"),
            "mds": (restarts, "正在为聚焦搜索整理索引。"),
            "mds_stores": (restarts, "存放聚焦搜索的索引。"),
            "mdworker": (restarts, "正在为聚焦搜索读取文件。"),
            "mdworker_shared": (restarts, "正在为聚焦搜索读取文件。"),
            "corespotlightd": (restarts, "提供聚焦搜索。"),
            "mediaanalysisd": (restarts, "正在分析照片和图库。"),
            "photoanalysisd": (restarts, "正在分析照片。"),
            "photolibraryd": (restarts, "管理照片图库。"),
            "cloudd": (restarts, "同步 iCloud 数据。"),
            "bird": (restarts, "同步 iCloud 里的文件。"),
            "nsurlsessiond": (restarts, "替 App 做后台传输。"),
            "coreaudiod": (restarts, "管理声音的播放和录制。"),
            "bluetoothd": (restarts, "管理蓝牙设备。"),
            "apsd": (restarts, "接收 Apple 推送。"),
            "sharingd": (restarts, "管理隔空投送和共享。"),
            "rapportd": (restarts, "发现附近的 Apple 设备。"),
            "searchpartyd": (restarts, "参与查找设备。"),
        ]
        XCTAssertEqual(expected.count, 32)
        XCTAssertTrue(Set(expected.keys).isSubset(of: Set(ProcessGlossary.entries.keys)))
        XCTAssertEqual(ProcessQuitSafety.canQuit.rawValue, "可以退出")
        XCTAssertEqual(ProcessQuitSafety.restarts.rawValue, "退出后会自动重启")
        XCTAssertEqual(ProcessQuitSafety.systemProcess.rawValue, "不建议退出（系统进程）")

        let banned = ["泄漏", "泄露", "leak", "危险", "告警", "异常", "独占", "可释放", "活动监视器", "真实占用", "footprint"]
        for (name, expectedEntry) in expected {
            let entry = ProcessGlossary.entry(for: name)
            XCTAssertEqual(entry?.quitSafety, expectedEntry.0, name)
            XCTAssertEqual(entry?.note, expectedEntry.1, name)
            XCTAssertEqual(ProcessGlossary.note(for: " \(name) "), expectedEntry.1, name)
            XCTAssertEqual(ProcessGlossary.notes[name], expectedEntry.1, name)
            let reason = entry?.reason ?? ""
            XCTAssertFalse(reason.isEmpty, name)
            XCTAssertNotEqual(reason, expectedEntry.1, name)
            let line = entry?.quitSafetyText ?? ""
            XCTAssertTrue(line.hasPrefix(expectedEntry.0.rawValue + "。"), name)
            XCTAssertTrue(line.contains(reason), name)
            let blob = "\(expectedEntry.1)\n\(reason)\n\(line)"
            for word in banned {
                XCTAssertFalse(blob.localizedCaseInsensitiveContains(word), "\(name) \(word)")
            }
            XCTAssertFalse(blob.contains("未知"), name)
        }
        XCTAssertNil(ProcessGlossary.entry(for: "Kernel_task"))
        XCTAssertNil(ProcessGlossary.note(for: "Kernel_task"))
    }

    func testAboutOneHundredEntriesEachHaveAJudgmentAndReason() {
        let names = Array(ProcessGlossary.entries.keys)
        XCTAssertGreaterThanOrEqual(names.count, 90)
        XCTAssertLessThanOrEqual(names.count, 120)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(ProcessGlossary.notes.count, names.count)

        let allowed: Set<String> = [
            "可以退出",
            "退出后会自动重启",
            "不建议退出（系统进程）",
        ]
        let banned = ["泄漏", "泄露", "leak", "危险", "告警", "异常", "独占", "可释放", "活动监视器", "真实占用", "footprint"]
        var seen: Set<ProcessQuitSafety> = []
        for name in names {
            XCTAssertFalse(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name)
            let entry = ProcessGlossary.entry(for: name)
            XCTAssertNotNil(entry, name)
            let note = entry?.note ?? ""
            let reason = entry?.reason ?? ""
            XCTAssertFalse(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name)
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name)
            XCTAssertNotEqual(note, reason, name)
            XCTAssertEqual(ProcessGlossary.note(for: " \(name) "), note, name)
            XCTAssertEqual(ProcessGlossary.notes[name], note, name)
            let judgment = entry?.quitSafety.rawValue ?? ""
            XCTAssertTrue(allowed.contains(judgment), name)
            if let entry {
                seen.insert(entry.quitSafety)
            }
            let line = entry?.quitSafetyText ?? ""
            XCTAssertTrue(line.hasPrefix(judgment + "。"), name)
            XCTAssertTrue(line.contains(reason), name)
            let flipped = name == name.lowercased() ? name.uppercased() : name.lowercased()
            if ProcessGlossary.entries[flipped] == nil {
                XCTAssertNil(ProcessGlossary.entry(for: flipped), name)
            }
            let blob = "\(note)\n\(reason)\n\(line)"
            for word in banned {
                XCTAssertFalse(blob.localizedCaseInsensitiveContains(word), "\(name) \(word)")
            }
            XCTAssertFalse(blob.contains("未知"), name)
        }
        XCTAssertEqual(seen, Set([.canQuit, .restarts, .systemProcess]))
    }

    func testNotesOmitBannedWords() {
        let banned = ["泄漏", "泄露", "leak", "危险", "告警", "异常", "独占", "可释放", "活动监视器", "真实占用", "footprint"]
        let blob = ProcessGlossary.notes.values.joined(separator: "\n")
        for word in banned {
            XCTAssertFalse(blob.localizedCaseInsensitiveContains(word), word)
        }
    }

    func testSidebarShowsTheNoteAndTheListDoesNot() throws {
        let sidebar = try source("Pulse/Views/ProcessDetailSidebar.swift")
        XCTAssertTrue(sidebar.contains("ProcessGlossary.note(for: detail.row.name)"))
        XCTAssertFalse(sidebar.contains("未知"))

        let list = try source("Pulse/Views/ProcessTablePane.swift")
        XCTAssertFalse(list.contains("ProcessGlossary"))

        let growth = try source("Pulse/Models/MemoryGrowthSignal.swift")
        let help = growth.range(of: "static let help")
        XCTAssertNotNil(help)
        XCTAssertFalse(growth.contains("ProcessGlossary"))
    }

    func testSidebarShowsQuitSafetyUnderTheNoteAndOtherSurfacesDoNot() throws {
        let sidebar = try source("Pulse/Views/ProcessDetailSidebar.swift")
        let newlines = sidebar.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        XCTAssertLessThanOrEqual(newlines, 500)
        let note = try XCTUnwrap(sidebar.range(of: "ProcessGlossary.note(for: detail.row.name)"))
        let judgment = try XCTUnwrap(sidebar.range(of: "quitSafetyJudgment(for: detail.row.name)"))
        XCTAssertLessThan(note.lowerBound, judgment.lowerBound)
        XCTAssertFalse(sidebar.contains("未知"))

        let extensionSource = try source("Pulse/Views/ProcessDetailSidebar+QuitSafety.swift")
        XCTAssertTrue(extensionSource.contains("if let entry = ProcessGlossary.entry(for: name)"))
        XCTAssertTrue(extensionSource.contains("Text(entry.quitSafetyText)"))
        XCTAssertFalse(extensionSource.contains("未知"))
        XCTAssertFalse(extensionSource.contains("Text(\"\")"))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let views = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Pulse/Views"),
            includingPropertiesForKeys: nil
        )
        let allowed: Set = ["ProcessDetailSidebar.swift", "ProcessDetailSidebar+QuitSafety.swift"]
        for url in views where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let mentionsGlossary = text.contains("ProcessGlossary") || text.contains("quitSafetyJudgment")
            if mentionsGlossary {
                XCTAssertTrue(allowed.contains(url.lastPathComponent), url.lastPathComponent)
            }
        }
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
