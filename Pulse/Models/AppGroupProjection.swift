import Foundation

/// Memory-tab toolbar chrome. Groups the rows already left by name, rising, and windowed filters.
enum AppGroupChrome {
    static let toggleTitle = "按 App"
    static let help = "同名进程合为一行。内存和线程相加。"

    static func showsToggle(page: DashboardPage) -> Bool {
        page == .memory
    }
}

/// Display projection. Does not write the sampler rows or the growth series.
enum AppGroupProjection {
    static func apply(rows: [ProcessRow], grouped: Bool) -> [ProcessRow] {
        guard grouped else { return rows }
        var buckets: [String: [ProcessRow]] = [:]
        var order: [String] = []
        for row in rows {
            if buckets[row.name] == nil {
                order.append(row.name)
            }
            buckets[row.name, default: []].append(row)
        }
        return order.compactMap { name in
            buckets[name].map(combine)
        }
    }

    /// ON moves the selection to the heaviest pid of that name. OFF keeps the current pid.
    static func selectedPid(current: Int32?, rows: [ProcessRow], grouped: Bool) -> Int32? {
        guard grouped, let current else { return current }
        guard let name = rows.first(where: { $0.pid == current })?.name else { return current }
        let sameName = rows.filter { $0.name == name }
        return combine(sameName).pid
    }

    static func combine(_ members: [ProcessRow]) -> ProcessRow {
        precondition(!members.isEmpty)
        let lead = members.max { lhs, rhs in
            if lhs.memoryBytes != rhs.memoryBytes {
                return lhs.memoryBytes < rhs.memoryBytes
            }
            return lhs.pid > rhs.pid
        } ?? members[0]
        let anyResident = members.contains { $0.memorySource == .resident }
        return ProcessRow(
            pid: lead.pid,
            name: lead.name,
            bundleIdentifier: lead.bundleIdentifier,
            executablePath: lead.executablePath,
            cpuPercent: sum(members.map(\.cpuPercent)),
            memoryBytes: members.reduce(0) { $0 &+ $1.memoryBytes },
            memorySource: anyResident ? .resident : .footprint,
            residentMemoryIsPartial: anyResident,
            threadCount: members.reduce(0) { $0 + $1.threadCount },
            diskReadBytesPerSecond: sum(members.map(\.diskReadBytesPerSecond)),
            diskWriteBytesPerSecond: sum(members.map(\.diskWriteBytesPerSecond)),
            groupedMemberCount: members.count
        )
    }

    /// Any missing sample stays missing. A real zero still adds.
    static func sum(_ values: [Double?]) -> Double? {
        var total = 0.0
        for value in values {
            guard let value else { return nil }
            total += value
        }
        return total
    }
}
