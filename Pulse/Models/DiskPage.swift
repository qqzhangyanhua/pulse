import Foundation

/// Display text for a host or process disk byte rate. Missing samples stay an em dash
/// and are never shown as 0 B/s.
enum DiskRateText {
    static let missing = NetworkRateText.missing

    static func string(_ bytesPerSecond: Double?) -> String {
        NetworkRateText.string(bytesPerSecond)
    }
}

/// Calm disk-page copy. Memory pressure wording stays on the memory page.
enum DiskPageCopy {
    static let sampling = "正在采样…"
    static let emptyTitle = "暂无磁盘数据"
    static let emptyMessage = "这一帧没有进程可显示。"
    static let failureTitle = "暂时读不到磁盘数据，稍后重试"
    static let failureMessage = "这轮采样没有回来，点重新采样再试。"
    static let retry = "重新采样"
    static let sidebarEmpty = "选一个进程看详情"
    static let readTitle = "读取"
    static let writeTitle = "写入"
    static let chartCollecting = sampling

    /// Overview slot. Missing host rates stay 「—」, never 「0 字节/秒」.
    static func overviewLine(rates: HostDiskRates) -> String {
        "\(readTitle) · \(DiskRateText.string(rates.readBytesPerSecond)) · \(writeTitle) · \(DiskRateText.string(rates.writeBytesPerSecond))"
    }

    /// Process-table cell pair. A nil rate is 「—」, never 「暂不可用」 or a fake 0.
    static func processRates(read: Double?, write: Double?) -> String {
        "\(DiskRateText.string(read)) · \(DiskRateText.string(write))"
    }
}

/// View-side rings of host read/write rates. A missing rate is skipped, never stored as 0.
struct SystemDiskHistory: Equatable, Sendable {
    private(set) var read: SystemCPUHistory
    private(set) var write: SystemCPUHistory

    init(limit: Int = 90) {
        read = SystemCPUHistory(limit: limit)
        write = SystemCPUHistory(limit: limit)
    }

    mutating func record(rates: HostDiskRates, at date: Date?) {
        read.record(percent: rates.readBytesPerSecond, at: date)
        write.record(percent: rates.writeBytesPerSecond, at: date)
    }

    mutating func reset() {
        read.reset()
        write.reset()
    }
}
