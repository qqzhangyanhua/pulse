import Foundation

enum ProcessQuitSafety: String, Equatable, Sendable {
    case canQuit = "可以退出"
    case restarts = "退出后会自动重启"
    case systemProcess = "不建议退出（系统进程）"
}

struct ProcessGlossaryEntry: Equatable, Sendable {
    var note: String
    var quitSafety: ProcessQuitSafety
    var reason: String

    /// Judgment, then the reason. Shown under the glossary note.
    var quitSafetyText: String {
        "\(quitSafety.rawValue)。\(reason)"
    }
}

/// Sentence plus a quit-safety judgment. Unknown names stay blank.
enum ProcessGlossary {
    static func note(for name: String) -> String? {
        entry(for: name)?.note
    }

    static func entry(for name: String) -> ProcessGlossaryEntry? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return entries[trimmed]
    }

    static var notes: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value.note) })
    }

    private static func row(
        _ note: String,
        _ quitSafety: ProcessQuitSafety,
        _ reason: String
    ) -> ProcessGlossaryEntry {
        ProcessGlossaryEntry(note: note, quitSafety: quitSafety, reason: reason)
    }

    static let entries: [String: ProcessGlossaryEntry] = [
        "kernel_task": row(
            "内核用来调度 CPU 的进程。",
            .systemProcess,
            "这是系统内核，结束后这台 Mac 无法继续工作。"
        ),
        "WindowServer": row(
            "把窗口画到屏幕上。",
            .systemProcess,
            "结束后，当前登录会话里的窗口会一起消失。"
        ),
        "loginwindow": row(
            "负责登录和注销。",
            .systemProcess,
            "它维持着这次登录，结束后会回到登录画面。"
        ),
        "launchd": row(
            "按系统安排启动其他进程。",
            .systemProcess,
            "它负责启动其它进程，结束后系统不再安排这些任务。"
        ),
        "mds": row(
            "正在为聚焦搜索整理索引。",
            .restarts,
            "聚焦搜索由它维护，结束后系统会再把它拉起来。"
        ),
        "mds_stores": row(
            "存放聚焦搜索的索引。",
            .restarts,
            "聚焦索引放在这里，结束后系统会再把它拉起来。"
        ),
        "mdworker": row(
            "正在为聚焦搜索读取文件。",
            .restarts,
            "这是聚焦搜索的一次读取，有工作时系统会再启动它。"
        ),
        "mdworker_shared": row(
            "正在为聚焦搜索读取文件。",
            .restarts,
            "这是聚焦搜索的一次读取，有工作时系统会再启动它。"
        ),
        "corespotlightd": row(
            "提供聚焦搜索。",
            .restarts,
            "聚焦搜索由它提供，结束后系统会再把它拉起来。"
        ),
        "mediaanalysisd": row(
            "正在分析照片和图库。",
            .restarts,
            "照片和图库的分析停一下，系统稍后会再启动它。"
        ),
        "photoanalysisd": row(
            "正在分析照片。",
            .restarts,
            "照片分析停一下，系统稍后会再启动它。"
        ),
        "photolibraryd": row(
            "管理照片图库。",
            .restarts,
            "图库暂时不可用，系统会再把它拉起来。"
        ),
        "cloudd": row(
            "同步 iCloud 数据。",
            .restarts,
            "iCloud 同步停一下，系统会再把它拉起来。"
        ),
        "bird": row(
            "同步 iCloud 里的文件。",
            .restarts,
            "iCloud 文件同步停一下，系统会再把它拉起来。"
        ),
        "nsurlsessiond": row(
            "替 App 做后台传输。",
            .restarts,
            "App 的后台传输停一下，系统会再把它拉起来。"
        ),
        "trustd": row(
            "检查证书。",
            .systemProcess,
            "证书检查经过它，结束后这项检查会停。"
        ),
        "syspolicyd": row(
            "检查 App 能否打开。",
            .systemProcess,
            "App 能否打开由它检查，结束后这项检查会停。"
        ),
        "coreaudiod": row(
            "管理声音的播放和录制。",
            .restarts,
            "声音会短暂停一下，系统会再把它拉起来。"
        ),
        "bluetoothd": row(
            "管理蓝牙设备。",
            .restarts,
            "蓝牙会短暂停一下，系统会再把它拉起来。"
        ),
        "runningboardd": row(
            "管理 App 是否还在运行。",
            .systemProcess,
            "它登记 App 是否还在运行，结束后这些状态对不上。"
        ),
        "cfprefsd": row(
            "读取和保存偏好设置。",
            .systemProcess,
            "各进程的偏好设置经过它，结束后读写会失败。"
        ),
        "distnoted": row(
            "在进程之间传递通知。",
            .systemProcess,
            "进程之间的通知经过它，结束后这些通知会中断。"
        ),
        "notifyd": row(
            "在进程之间传递系统通知。",
            .systemProcess,
            "系统通知经过它，结束后这些通知会中断。"
        ),
        "apsd": row(
            "接收 Apple 推送。",
            .restarts,
            "Apple 推送会短暂停一下，系统会再把它拉起来。"
        ),
        "sharingd": row(
            "管理隔空投送和共享。",
            .restarts,
            "隔空投送和共享会停一下，系统会再把它拉起来。"
        ),
        "rapportd": row(
            "发现附近的 Apple 设备。",
            .restarts,
            "发现附近设备会停一下，系统会再把它拉起来。"
        ),
        "searchpartyd": row(
            "参与查找设备。",
            .restarts,
            "查找设备会停一下，系统会再把它拉起来。"
        ),
        "tccd": row(
            "记住隐私权限的选择。",
            .systemProcess,
            "隐私权限的选择记在这里，结束后这些选择对不上。"
        ),
        "powerd": row(
            "管理睡眠和电源。",
            .systemProcess,
            "它管理睡眠和电源，结束后这些策略不再生效。"
        ),
        "fseventsd": row(
            "观察文件有没有变化。",
            .systemProcess,
            "文件变化的通知经过它，结束后这项通知会停。"
        ),
        "configd": row(
            "管理系统和网络配置。",
            .systemProcess,
            "它维护系统和网络配置，结束后这些配置不再更新。"
        ),
        "logd": row(
            "收集系统日志。",
            .systemProcess,
            "它收集系统日志，结束后这一段日志不再写入。"
        ),
    ]
}
