import Foundation

/// One held sleep assertion, already turned into calm copy.
struct SleepAssertionRow: Equatable, Sendable, Identifiable {
    var id: String
    var pid: Int32
    var name: String
    var typeText: String
    var durationText: String
}

enum SleepAssertionCopy {
    static let title = "阻止睡眠"
    static let empty = "没有进程在阻止睡眠"
}

/// Pure decode of a dictionary shaped like `IOPMCopyAssertionsByProcess`.
/// Keys are pids. Values are arrays of assertion dictionaries.
enum SleepAssertionDecoder {
    static func rows(from assertionsByProcess: [AnyHashable: Any], now: Date) -> [SleepAssertionRow] {
        var held: [Held] = []
        var order = 0
        for (key, value) in assertionsByProcess {
            guard let pid = processIdentifier(from: key) else { continue }
            for entry in assertionDictionaries(from: value) {
                if entry["AssertTimedOutWhen"] != nil { continue }
                if isReleased(entry["AssertLevel"]) { continue }
                let typed = typeLabel(entry["AssertType"])
                held.append(Held(
                    pid: pid,
                    rawType: typed.raw,
                    start: startDate(entry["AssertStartWhen"]),
                    name: processName(entry["Process Name"]),
                    typeText: typed.label,
                    order: order
                ))
                order += 1
            }
        }
        held.sort { lhs, rhs in
            if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
            if lhs.rawType != rhs.rawType { return lhs.rawType < rhs.rawType }
            switch (lhs.start, rhs.start) {
            case let (left?, right?) where left != right:
                return left < right
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                return lhs.order < rhs.order
            }
        }
        var seen: [Int32: Int] = [:]
        return held.map { item in
            let index = seen[item.pid, default: 0]
            seen[item.pid] = index + 1
            return SleepAssertionRow(
                id: "\(item.pid)#\(index)",
                pid: item.pid,
                name: item.name,
                typeText: item.typeText,
                durationText: durationText(from: item.start, now: now)
            )
        }
    }

    private struct Held {
        var pid: Int32
        var rawType: String
        var start: Date?
        var name: String
        var typeText: String
        var order: Int
    }

    private static let typeNames: [String: String] = [
        "PreventUserIdleSystemSleep": "阻止系统睡眠",
        "NoIdleSleepAssertion": "阻止系统睡眠",
        "PreventUserIdleDisplaySleep": "阻止显示器睡眠",
        "NoDisplaySleepAssertion": "阻止显示器睡眠",
        "InternalPreventDisplaySleep": "阻止显示器睡眠",
        "PreventSystemSleep": "阻止进入睡眠",
        "DenySystemSleep": "阻止进入睡眠",
        "InternalPreventSleep": "阻止进入睡眠",
        "PreventDiskIdle": "阻止磁盘睡眠",
        "UserIsActive": "报告用户活动",
        "SystemIsActive": "报告用户活动",
        "DeclareUserActivity": "报告用户活动",
        "BackgroundTask": "后台任务",
        "NetworkClientActive": "网络活动",
        "ApplePushServiceTask": "推送任务",
        "InteractivePushServiceTask": "交互推送",
        "ExternalMedia": "外接媒体",
        "CPUBoundAssertion": "持续运算",
        "DisplayWake": "点亮显示器",
        "EnableIdleSleep": "允许空闲睡眠",
        "AwakeOnReservePower": "备用电源时不睡眠",
    ]

    private static func processIdentifier(from key: AnyHashable) -> Int32? {
        if let value = key as? Int32 { return value }
        if let value = key as? Int { return Int32(exactly: value) }
        if let value = key as? Int64 { return Int32(exactly: value) }
        if let value = key as? UInt32 { return Int32(exactly: value) }
        if let value = key as? UInt { return Int32(exactly: value) }
        if let number = key as? NSNumber {
            return Int32(exactly: number.int64Value)
        }
        return nil
    }

    private static func assertionDictionaries(from value: Any) -> [[String: Any]] {
        let items: [Any]
        if let list = value as? [Any] {
            items = list
        } else if let list = value as? NSArray {
            items = list.compactMap { $0 }
        } else {
            return []
        }
        return items.compactMap(dictionary(from:))
    }

    private static func dictionary(from value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        if let dict = value as? [AnyHashable: Any] {
            var fields: [String: Any] = [:]
            for (key, item) in dict {
                guard let name = key as? String else { continue }
                fields[name] = item
            }
            return fields
        }
        if let dict = value as? NSDictionary {
            var fields: [String: Any] = [:]
            for (key, item) in dict {
                guard let name = key as? String else { continue }
                fields[name] = item
            }
            return fields
        }
        return nil
    }

    private static func isReleased(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let number = value as? NSNumber { return number.intValue == 0 }
        if let int = value as? Int { return int == 0 }
        if let int = value as? Int32 { return int == 0 }
        if let int = value as? Int64 { return int == 0 }
        return false
    }

    private static func typeLabel(_ value: Any?) -> (raw: String, label: String) {
        guard let text = value as? String else { return ("", "—") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", "—") }
        return (trimmed, typeNames[trimmed] ?? "其它")
    }

    private static func processName(_ value: Any?) -> String {
        guard let text = value as? String else { return "—" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private static func startDate(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let seconds = value as? TimeInterval { return Date(timeIntervalSince1970: seconds) }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    /// Under a minute keeps seconds. Longer spans drop leftover seconds.
    /// Missing, future, and non-finite starts stay 「—」. A real zero is 「0 秒」.
    private static func durationText(from start: Date?, now: Date) -> String {
        guard let start else { return "—" }
        let seconds = now.timeIntervalSince(start)
        guard seconds.isFinite, seconds >= 0, seconds <= Double(Int.max) else { return "—" }
        let whole = Int(seconds)
        if whole < 60 { return "\(whole) 秒" }
        var minutes = whole / 60
        let days = minutes / (24 * 60)
        minutes %= 24 * 60
        let hours = minutes / 60
        minutes %= 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) 天") }
        if hours > 0 { parts.append("\(hours) 小时") }
        if minutes > 0 { parts.append("\(minutes) 分钟") }
        return parts.joined(separator: " ")
    }
}
