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
        // 名字本身不好懂的系统进程、开发工具和浏览器辅助进程。键是精确进程名。
        "syslogd": row("接收各进程交来的系统日志。", .systemProcess, "系统日志经过它，结束后这一段不再写入。"),
        "UserEventAgent": row("运行登录之后的用户代理。", .restarts, "这些代理会停一下，系统会再把它拉起来。"),
        "ReportCrash": row("把进程崩溃写成报告。", .restarts, "崩溃报告会停一下，系统会再把它拉起来。"),
        "spindump": row("为卡住的进程采集一份样本。", .restarts, "这次采样会停，系统下次需要时会再启动它。"),
        "symptomsd": row("收集网络和系统状况，供诊断使用。", .restarts, "状况收集会停一下，系统会再把它拉起来。"),
        "locationd": row("向 App 提供定位。", .restarts, "定位会短暂停一下，系统会再把它拉起来。"),
        "coreduetd": row("记录使用习惯，供系统建议使用。", .restarts, "这项记录会停一下，系统会再把它拉起来。"),
        "suggestd": row("生成输入和搜索建议。", .restarts, "建议会停一下，系统会再把它拉起来。"),
        "parsecd": row("替聚焦和 Siri 查询本机内容。", .restarts, "这类查询会停一下，系统会再把它拉起来。"),
        "assistantd": row("响应 Siri 的请求。", .restarts, "Siri 会短暂停一下，系统会再把它拉起来。"),
        "coreservicesd": row("协调打开服务和一部分系统功能。", .systemProcess, "这些协调经过它，结束后会停。"),
        "lsd": row("登记哪个 App 可以打开哪类文件。", .systemProcess, "打开文件时要查这份登记，结束后会对不上。"),
        "Dock": row("显示程序坞。", .restarts, "程序坞会消失一下，系统会再把它拉起来。"),
        "Finder": row("显示访达窗口和桌面。", .restarts, "访达会关掉，系统会再把它拉起来。"),
        "SystemUIServer": row("显示菜单栏右侧的状态图标。", .restarts, "这些图标会消失一下，系统会再把它拉起来。"),
        "ControlCenter": row("显示控制中心。", .restarts, "控制中心会关掉，系统会再把它拉起来。"),
        "NotificationCenter": row("显示通知中心。", .restarts, "通知中心会关掉，系统会再把它拉起来。"),
        "Spotlight": row("显示聚焦搜索的输入界面。", .restarts, "这个界面会关掉，系统会再把它拉起来。"),
        "deleted": row("在空间变紧时清理可以再生的缓存。", .restarts, "清理会停一下，系统会再把它拉起来。"),
        "mDNSResponder": row("查询域名，并发现局域网里的设备。", .restarts, "域名查询会短暂停一下，系统会再把它拉起来。"),
        "airportd": row("管理 Wi-Fi 连接。", .restarts, "Wi-Fi 会短暂停一下，系统会再把它拉起来。"),
        "amfid": row("在启动代码前检查签名。", .systemProcess, "新进程的签名检查经过它，结束后这项检查会停。"),
        "secd": row("读写钥匙串里的项目。", .systemProcess, "钥匙串读写经过它，结束后这些读写会失败。"),
        "opendirectoryd": row("查询用户、组和目录信息。", .systemProcess, "这些查询经过它，结束后会对不上。"),
        "diskarbitrationd": row("安排磁盘的挂载和推出。", .systemProcess, "挂载和推出经过它，结束后这项安排会停。"),
        "fileproviderd": row("接入 iCloud 和其他文件提供方。", .restarts, "这些文件会暂时接不上，系统会再把它拉起来。"),
        "backupd": row("执行时间机器备份。", .restarts, "正在进行的备份会停，系统会再把它拉起来。"),
        "WindowManager": row("管理窗口的大小和摆放。", .restarts, "窗口摆放会停一下，系统会再把它拉起来。"),
        "hidd": row("接收键盘、鼠标和触控板的输入。", .restarts, "输入会短暂停一下，系统会再把它拉起来。"),
        "pboard": row("在 App 之间传递剪贴板内容。", .restarts, "复制和粘贴会短暂停一下，系统会再把它拉起来。"),
        "Google Chrome": row("谷歌浏览器本身。", .canQuit, "结束后它的窗口会关掉，不会自己再打开。"),
        "Google Chrome Helper": row("谷歌浏览器拆出去的辅助进程。", .restarts, "相关页面还在时，浏览器会再启动一个。"),
        "Google Chrome Helper (Renderer)": row("谷歌浏览器里负责绘制页面的进程。", .restarts, "对应页面还开着时，浏览器会再启动一个。"),
        "Google Chrome Helper (GPU)": row("谷歌浏览器里负责图形的进程。", .restarts, "浏览器还开着时，它会再启动这个图形进程。"),
        "Google Chrome Helper (Plugin)": row("谷歌浏览器里运行插件的进程。", .restarts, "插件还在用时，浏览器会再启动一个。"),
        "chrome_crashpad_handler": row("谷歌浏览器用来收下崩溃报告的进程。", .canQuit, "结束后它不再收下这次崩溃报告，浏览器本身还在。"),
        "Safari": row("Safari 浏览器本身。", .canQuit, "结束后它的窗口会关掉，不会自己再打开。"),
        "com.apple.WebKit.WebContent": row("替 Safari 等 App 绘制并运行网页。", .restarts, "对应网页还开着时，使用它的 App 会再启动一个。"),
        "com.apple.WebKit.Networking": row("替 Safari 等 App 发起网页的网络请求。", .restarts, "网页还开着时，使用它的 App 会再启动这个网络进程。"),
        "com.apple.WebKit.GPU": row("替 Safari 等 App 做网页里的图形。", .restarts, "网页还开着时，使用它的 App 会再启动这个图形进程。"),
        "firefox": row("Firefox 浏览器本身。", .canQuit, "结束后它的窗口会关掉，不会自己再打开。"),
        "plugin-container": row("Firefox 用来隔离网页或插件的进程。", .restarts, "对应网页还开着时，Firefox 会再启动一个。"),
        "Microsoft Edge": row("Edge 浏览器本身。", .canQuit, "结束后它的窗口会关掉，不会自己再打开。"),
        "Microsoft Edge Helper": row("Edge 拆出去的辅助进程。", .restarts, "相关页面还在时，Edge 会再启动一个。"),
        "Microsoft Edge Helper (Renderer)": row("Edge 里负责绘制页面的进程。", .restarts, "对应页面还开着时，Edge 会再启动一个。"),
        "Microsoft Edge Helper (GPU)": row("Edge 里负责图形的进程。", .restarts, "Edge 还开着时，它会再启动这个图形进程。"),
        "Chromium": row("Chromium 浏览器本身。", .canQuit, "结束后它的窗口会关掉，不会自己再打开。"),
        "Xcode": row("苹果的开发工具，用来编写和调试 App。", .canQuit, "结束后当前的编写和调试会停，不会自己再打开。"),
        "SourceKitService": row("为 Xcode 做代码索引和补全。", .restarts, "Xcode 还开着时，它会再启动这项服务。"),
        "com.apple.dt.SKAgent": row("替 Xcode 跑源代码服务。", .restarts, "Xcode 还开着时，它会再启动这个服务。"),
        "swift-frontend": row("正在把 Swift 源码编译成产物。", .canQuit, "结束后这一次编译会停，不会自己再开始。"),
        "node": row("正在运行一段 Node.js 程序。", .canQuit, "结束后这段 Node.js 程序会停，不会自己再开始。"),
        "Python": row("正在运行一段 Python 程序。", .canQuit, "结束后这段 Python 程序会停，不会自己再开始。"),
        "python3": row("正在运行一段 Python 3 程序。", .canQuit, "结束后这段 Python 3 程序会停，不会自己再开始。"),
        "java": row("正在运行一段 Java 程序。", .canQuit, "结束后这段 Java 程序会停，不会自己再开始。"),
        "ruby": row("正在运行一段 Ruby 程序。", .canQuit, "结束后这段 Ruby 程序会停，不会自己再开始。"),
        "Code": row("Visual Studio Code 编辑器本身。", .canQuit, "结束后编辑器会关掉，不会自己再打开。"),
        "Code Helper": row("Visual Studio Code 拆出去的辅助进程。", .restarts, "编辑器还开着时，它会再启动一个。"),
        "Code Helper (Renderer)": row("Visual Studio Code 里负责绘制界面的进程。", .restarts, "窗口还开着时，编辑器会再启动一个。"),
        "Code Helper (GPU)": row("Visual Studio Code 里负责图形的进程。", .restarts, "编辑器还开着时，它会再启动这个图形进程。"),
        "Code Helper (Plugin)": row("Visual Studio Code 里运行扩展的进程。", .restarts, "扩展还在用时，编辑器会再启动一个。"),
        "Simulator": row("苹果的模拟器，用来运行 iOS 等系统。", .canQuit, "结束后模拟器会关掉，不会自己再打开。"),
        "com.apple.CoreSimulator.CoreSimulatorService": row("在后台维持模拟器的运行环境。", .restarts, "模拟器还要用时，系统会再把它拉起来。"),
        "lldb-rpc-server": row("调试器用来和控制目标对话的进程。", .canQuit, "结束后这一次调试对话会停，不会自己再开始。"),
        "com.docker.backend": row("Docker Desktop 的后台服务。", .restarts, "Docker Desktop 还开着时，它会再启动这个服务。"),
        "com.docker.vmnetd": row("为 Docker 提供虚拟机网络。", .restarts, "这项网络会停一下，系统会再把它拉起来。"),
        "git": row("正在执行一次 Git 操作。", .canQuit, "结束后这一次操作会停，不会自己再开始。"),
        "Docker Desktop": row("Docker Desktop 应用本身。", .canQuit, "结束后它的界面会关掉，不会自己再打开。"),
    ]
}
