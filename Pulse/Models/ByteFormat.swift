import Foundation

/// Host and process byte/rate copy. Missing samples stay an em dash elsewhere;
/// a real 0 is formatted as 0, never turned into a fake "0 GB" placeholder.
enum ByteFormat {
    static func memory(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 字节" }
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return grouped(gib, maxDecimals: 2) + " GB"
        }
        let mib = Double(bytes) / 1_048_576
        if mib >= 1 {
            return grouped(mib, maxDecimals: 1) + " MB"
        }
        let kib = Double(bytes) / 1_024
        if kib >= 1 {
            return grouped(kib, maxDecimals: 0) + " KB"
        }
        return "\(bytes) 字节"
    }

    static func gibWhole(_ bytes: UInt64) -> String {
        let gib = (Double(bytes) / 1_073_741_824).rounded()
        return String(format: "%.0f GB", gib)
    }

    static func cpu(_ value: Double?) -> String {
        CPUPercentText.string(value)
    }

    static func networkRate(_ bytesPerSecond: Double?) -> String {
        NetworkRateText.string(bytesPerSecond)
    }

    static func diskRate(_ bytesPerSecond: Double?) -> String {
        DiskRateText.string(bytesPerSecond)
    }

    static func wholePercent(value: Double) -> String {
        String(format: "%.0f%%", (value * 100).rounded())
    }

    static func wholePercent(part: UInt64, total: UInt64) -> String {
        guard total > 0 else { return "0%" }
        return wholePercent(value: Double(part) / Double(total))
    }

    static func share(part: UInt64, total: UInt64) -> String {
        guard total > 0 else { return "0%" }
        let percent = (Double(part) / Double(total)) * 100
        if part > 0, percent < 0.1 { return "<0.1%" }
        if percent < 10 { return String(format: "%.1f%%", percent) }
        return String(format: "%.0f%%", percent)
    }

    static func coreLoad(cpuPercent: Double?, processorCount: Int) -> String {
        let total = max(processorCount, 1)
        guard let cpuPercent else { return "— (共 \(total) 个)" }
        let cores = cpuPercent / 100 * Double(total)
        return String(format: "%.1f 个内核 (共 %d 个)", cores, total)
    }

    static func clock(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    // NumberFormatter is mutable. One instance per thread: toolbar byte text can run off the main thread.
    private static func grouped(_ value: Double, maxDecimals: Int) -> String {
        let grouping = abs(value) >= 1000
        let formatter = groupedFormatter(maxDecimals: maxDecimals, grouping: grouping)
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxDecimals)f", value)
    }

    private static func groupedFormatter(maxDecimals: Int, grouping: Bool) -> NumberFormatter {
        let key = "Pulse.ByteFormat.\(maxDecimals).\(grouping)"
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
