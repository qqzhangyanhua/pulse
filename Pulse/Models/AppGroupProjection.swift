import Foundation

/// Memory and CPU toolbar chrome. Groups the rows already left by name, rising, and windowed filters.
enum AppGroupChrome {
    static let toggleTitle = "按 App"
    static let help = "同名进程合为一行。内存、线程、CPU、能耗和唤醒相加。"

    static func applies(on page: DashboardPage) -> Bool {
        page == .memory || page == .cpu
    }

    static func showsToggle(page: DashboardPage) -> Bool {
        applies(on: page)
    }

    /// False only while grouping is on and this page merges rows.
    static func showsProcessTreeButton(groupedByApp: Bool, page: DashboardPage) -> Bool {
        !(groupedByApp && applies(on: page))
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
        let energy = ProcessEnergyGroup.sum(members.map(\.energyWatts))
        let wakeups = ProcessEnergyGroup.sum(members.map(\.wakeupsPerSecond))
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
            energyWatts: energy.value,
            wakeupsPerSecond: wakeups.value,
            energyReadingIsPartial: energy.isPartial,
            wakeupReadingIsPartial: wakeups.isPartial,
            groupedMemberCount: members.count,
            parentPid: lead.parentPid
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
