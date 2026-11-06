import Foundation

/// On-device one-liners for common system processes. Unknown names stay blank.
enum ProcessGlossary {
    static func note(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return notes[trimmed]
    }

    static let notes: [String: String] = [
        "kernel_task": "内核用来调度 CPU 的进程。",
        "WindowServer": "把窗口画到屏幕上。",
        "loginwindow": "负责登录和注销。",
        "launchd": "按系统安排启动其他进程。",
        "mds": "正在为聚焦搜索整理索引。",
        "mds_stores": "存放聚焦搜索的索引。",
        "mdworker": "正在为聚焦搜索读取文件。",
        "mdworker_shared": "正在为聚焦搜索读取文件。",
        "corespotlightd": "提供聚焦搜索。",
        "mediaanalysisd": "正在分析照片和图库。",
        "photoanalysisd": "正在分析照片。",
        "photolibraryd": "管理照片图库。",
        "cloudd": "同步 iCloud 数据。",
        "bird": "同步 iCloud 里的文件。",
        "nsurlsessiond": "替 App 做后台传输。",
        "trustd": "检查证书。",
        "syspolicyd": "检查 App 能否打开。",
        "coreaudiod": "管理声音的播放和录制。",
        "bluetoothd": "管理蓝牙设备。",
        "runningboardd": "管理 App 是否还在运行。",
        "cfprefsd": "读取和保存偏好设置。",
        "distnoted": "在进程之间传递通知。",
        "notifyd": "在进程之间传递系统通知。",
        "apsd": "接收 Apple 推送。",
        "sharingd": "管理隔空投送和共享。",
        "rapportd": "发现附近的 Apple 设备。",
        "searchpartyd": "参与查找设备。",
        "tccd": "记住隐私权限的选择。",
        "powerd": "管理睡眠和电源。",
        "fseventsd": "观察文件有没有变化。",
        "configd": "管理系统和网络配置。",
        "logd": "收集系统日志。",
    ]
}
