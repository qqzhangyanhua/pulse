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

    private static func grouped(_ value: Double, maxDecimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxDecimals
        formatter.usesGroupingSeparator = abs(value) >= 1000
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxDecimals)f", value)
    }
}

/// Calm network-page copy. Memory pressure wording stays on the memory page.
enum NetworkPageCopy {
    static let sampling = "正在采样…"
    static let emptyTitle = "还没有进程数据"
    static let emptyMessage = "这一帧没有进程可显示。"
    static let failureTitle = "暂时读不到网络数据"
    static let failureMessage = "这轮采样没有回来，点重新采样再试。"
    static let retry = "重新采样"
    static let sidebarEmpty = "选一个进程看详情"
    static let inboundTitle = "下行"
    static let outboundTitle = "上行"
    static let columnTitle = "网络"
    static let processNetworkUnavailable = ProcessNetworkAvailability.unavailable.label
    static let chartCollecting = "曲线采集中"

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
