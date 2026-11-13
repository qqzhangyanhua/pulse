import Foundation

/// Display text for a host byte rate. Missing samples stay an em dash and are never shown as 0 B/s.
enum NetworkRateText {
    static let missing = "—"

    static func string(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return missing }
        return format(abs(bytesPerSecond)) + "/秒"
    }

    private static func format(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond == 0 { return "0 字节" }
        let gib = bytesPerSecond / 1_073_741_824
        if gib >= 1 {
            return grouped(gib, maxDecimals: 2) + " GB"
        }
        let mib = bytesPerSecond / 1_048_576
        if mib >= 1 {
            return grouped(mib, maxDecimals: 1) + " MB"
        }
        let kib = bytesPerSecond / 1_024
        if kib >= 1 {
            return grouped(kib, maxDecimals: 0) + " KB"
        }
        return grouped(bytesPerSecond, maxDecimals: 0) + " 字节"
    }

    // NumberFormatter is mutable. One instance per thread, same as ByteFormat.
    private static func grouped(_ value: Double, maxDecimals: Int) -> String {
        let grouping = abs(value) >= 1000
        let formatter = groupedFormatter(maxDecimals: maxDecimals, grouping: grouping)
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxDecimals)f", value)
    }

    private static func groupedFormatter(maxDecimals: Int, grouping: Bool) -> NumberFormatter {
        let key = "Pulse.NetworkRateText.\(maxDecimals).\(grouping)"
        let dictionary = Thread.current.threadDictionary
        if let formatter = dictionary[key] as? NumberFormatter {
            return formatter
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = posix
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxDecimals
        formatter.usesGroupingSeparator = grouping
        dictionary[key] = formatter
        return formatter
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
}

/// Calm network-page copy. Memory pressure wording stays on the memory page.
enum NetworkPageCopy {
    static let sampling = "正在采样…"
    static let emptyTitle = "还没有进程数据"
    static let emptyMessage = "这一帧没有进程可显示。"
    static let failureTitle = "暂时读不到网络数据"
    static let failureMessage = SamplingRetryChrome.overviewFailureMessage
    static let retry = SamplingRetryChrome.buttonTitle
    static let sidebarEmpty = "选一个进程看详情"
    static let inboundTitle = "下行"
    static let outboundTitle = "上行"
    static let columnTitle = "网络"
    static let processNetworkUnavailable = ProcessNetworkAvailability.unavailable.label
    /// Tooltip only. The cells stay 「暂不可用」 / the detail sentence.
    static let processRateHelp = "没有进程速率。主机下行和上行在总览。"
    static let chartCollecting = "曲线采集中"
    static let connectionTitle = "连接"
    static let connectionStatusTitle = "状态"
    static let connectionTypeTitle = "类型"
    static let connectionConnected = "已连接"
    static let connectionDisconnected = "未连接"
    static let connectionRequiresLogin = "需要登录或配置"
    static let connectionWiFi = "Wi-Fi"
    static let connectionEthernet = "以太网"
    static let connectionOther = "其它"

    /// Overview slot. Missing host rates stay 「—」, never 「0 字节/秒」.
    static func overviewLine(rates: HostNetworkRates) -> String {
        "\(inboundTitle) · \(NetworkRateText.string(rates.inboundBytesPerSecond)) · \(outboundTitle) · \(NetworkRateText.string(rates.outboundBytesPerSecond))"
    }
}

/// View-side rings of host inbound/outbound rates. A missing rate is skipped, never stored as 0.
struct SystemNetworkHistory: Equatable, Sendable {
    private(set) var inbound: SystemCPUHistory
    private(set) var outbound: SystemCPUHistory

    init(limit: Int = 90) {
        inbound = SystemCPUHistory(limit: limit)
        outbound = SystemCPUHistory(limit: limit)
    }

    mutating func record(rates: HostNetworkRates, at date: Date?) {
        inbound.record(percent: rates.inboundBytesPerSecond, at: date)
        outbound.record(percent: rates.outboundBytesPerSecond, at: date)
    }

    mutating func reset() {
        inbound.reset()
        outbound.reset()
    }
}
