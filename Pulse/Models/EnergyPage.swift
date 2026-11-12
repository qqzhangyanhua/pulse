import Foundation

enum EnergyPagePhase: Equatable, Sendable {
    case sampling
    case processListFailed
    case sampleFailed
    case empty
    case filteredEmpty
    case ready
}

/// Ranking span on the energy page. Not a third resource tab.
enum EnergyRankingSpan: Equatable, Hashable, Sendable {
    case oneMinute
    case oneHour
}

enum EnergyPageCopy {
    static let headline = "最近 1 分钟平均功率"
    static let explanation = "用这段时间里累计的能耗除以实际时长。不足 1 分钟时用已经采到的时长。读不到显示「—」，不显示 0。这不是活动监视器的能耗影响分数。"
    static let hourHeadline = "最近 1 小时平均功率"
    static let hourExplanation = "把这一小时里有读数的分钟耗电量相加，再除以这些分钟的实际时长。缺读数的分钟不补 0。这不是活动监视器的能耗影响分数。"

    static func headline(for span: EnergyRankingSpan) -> String {
        switch span {
        case .oneMinute:
            return headline
        case .oneHour:
            return hourHeadline
        }
    }

    static func explanation(for span: EnergyRankingSpan) -> String {
        switch span {
        case .oneMinute:
            return explanation
        case .oneHour:
            return hourExplanation
        }
    }

    static let samplingTitle = "正在采样…"
    static let processListFailedTitle = "暂时无法列出进程"
    static let processListFailedMessage = SamplingRetryChrome.processListFailedMessage
    static let sampleFailedTitle = "进程列表还没有数据"
    static let sampleFailedMessage = SamplingRetryChrome.overviewFailureMessage
    static let emptyTitle = "还没有进程数据"
    static let emptyMessage = "这一帧没有进程可显示。"
    static let filteredEmptyTitle = "没有匹配的 App"
    static let filteredEmptyMessage = "换个名称试试，或清空过滤。"
    static let filteredEmptyButton = "清空过滤"
    static let retry = SamplingRetryChrome.buttonTitle
    static let impactTitle = ProcessEnergyText.impactTitle
    static let wakeTitle = ProcessEnergyText.wakeTitle
    static let columns = [ProcessColumnTitle.name, impactTitle, wakeTitle]
}

/// One displayed energy-page rate. Partial means a grouped sum skipped a nil member.
struct EnergyDisplayReading: Equatable, Sendable {
    let watts: Double?
    let wakeupsPerSecond: Double?
    let energyReadingIsPartial: Bool
    let wakeupReadingIsPartial: Bool

    var rates: ProcessEnergyRates {
        ProcessEnergyRates(watts: watts, wakeupsPerSecond: wakeupsPerSecond)
    }
}

/// Rows the energy table shows, plus window rates keyed by those rows' pids.
struct EnergyPageDisplay: Equatable, Sendable {
    let rows: [ProcessRow]
    let readings: [Int32: EnergyDisplayReading]

    var rates: [Int32: ProcessEnergyRates] {
        readings.mapValues(\.rates)
    }
}

/// Energy-page filter, order, and empty state. Does not read `energyWatts`.
enum EnergyPage {
    static func filtered(_ rows: [ProcessRow], query: String) -> [ProcessRow] {
        ProcessNameFilter.apply(rows, query: query)
    }

    /// Name-filtered rows in. Grouped rows keep the representative's sampled watts.
    /// The reading table is the window sum, keyed by the displayed pid.
    static func display(
        rows: [ProcessRow],
        windowRates: [Int32: ProcessEnergyRates],
        grouped: Bool
    ) -> EnergyPageDisplay {
        guard grouped else {
            return EnergyPageDisplay(
                rows: rows,
                readings: windowRates.mapValues { rate in
                    EnergyDisplayReading(
                        watts: rate.watts,
                        wakeupsPerSecond: rate.wakeupsPerSecond,
                        energyReadingIsPartial: false,
                        wakeupReadingIsPartial: false
                    )
                }
            )
        }
        var buckets: [String: [ProcessRow]] = [:]
        var order: [String] = []
        for row in rows {
            if buckets[row.name] == nil {
                order.append(row.name)
            }
            buckets[row.name, default: []].append(row)
        }
        var displayed: [ProcessRow] = []
        var readings: [Int32: EnergyDisplayReading] = [:]
        for name in order {
            guard let members = buckets[name], !members.isEmpty else { continue }
            let lead = representative(members)
            let watts = ProcessEnergyGroup.sum(members.map { windowRates[$0.pid]?.watts })
            let wakeups = ProcessEnergyGroup.sum(members.map { windowRates[$0.pid]?.wakeupsPerSecond })
            displayed.append(copying(lead, memberCount: members.count))
            readings[lead.pid] = EnergyDisplayReading(
                watts: watts.value,
                wakeupsPerSecond: wakeups.value,
                energyReadingIsPartial: watts.isPartial,
                wakeupReadingIsPartial: wakeups.isPartial
            )
        }
        return EnergyPageDisplay(rows: displayed, readings: readings)
    }

    static func sorted(
        _ rows: [ProcessRow],
        windowRates: [Int32: ProcessEnergyRates],
        grouped: Bool,
        sort: ProcessTableSort
    ) -> [ProcessRow] {
        let shown = display(rows: rows, windowRates: windowRates, grouped: grouped)
        return ordered(shown.rows, rates: shown.rates, sort: sort)
    }

    static func ordered(
        _ rows: [ProcessRow],
        rates: [Int32: ProcessEnergyRates],
        sort: ProcessTableSort
    ) -> [ProcessRow] {
        rows.sorted { lhs, rhs in
            if sort.column == .name {
                if lhs.name != rhs.name {
                    let ascending = lhs.name < rhs.name
                    return sort.descending ? !ascending : ascending
                }
                return lhs.pid < rhs.pid
            }
            let left = metric(lhs.pid, column: sort.column, rates: rates)
            let right = metric(rhs.pid, column: sort.column, rates: rates)
            switch (left, right) {
            case (nil, nil):
                return lhs.pid < rhs.pid
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case let (lhsValue?, rhsValue?):
                if lhsValue == rhsValue { return lhs.pid < rhs.pid }
                return sort.descending ? lhsValue > rhsValue : lhsValue < rhsValue
            }
        }
    }

    static func phase(
        loadState: LoadState,
        processCount: Int,
        visibleCount: Int,
        hasActiveNameFilter: Bool,
        processListFailed: Bool
    ) -> EnergyPagePhase {
        if processCount == 0 {
            switch loadState {
            case .sampling:
                return .sampling
            case .failed:
                return .sampleFailed
            case .ready:
                return processListFailed ? .processListFailed : .empty
            }
        }
        if visibleCount == 0, hasActiveNameFilter {
            return .filteredEmpty
        }
        return .ready
    }

    /// Same lead as `AppGroupProjection.combine`: most memory, then the smaller pid.
    private static func representative(_ members: [ProcessRow]) -> ProcessRow {
        members.max { lhs, rhs in
            if lhs.memoryBytes != rhs.memoryBytes {
                return lhs.memoryBytes < rhs.memoryBytes
            }
            return lhs.pid > rhs.pid
        } ?? members[0]
    }

    private static func copying(_ lead: ProcessRow, memberCount: Int) -> ProcessRow {
        ProcessRow(
            pid: lead.pid,
            name: lead.name,
            bundleIdentifier: lead.bundleIdentifier,
            executablePath: lead.executablePath,
            cpuPercent: lead.cpuPercent,
            memoryBytes: lead.memoryBytes,
            memorySource: lead.memorySource,
            residentMemoryIsPartial: lead.residentMemoryIsPartial,
            threadCount: lead.threadCount,
            diskReadBytesPerSecond: lead.diskReadBytesPerSecond,
            diskWriteBytesPerSecond: lead.diskWriteBytesPerSecond,
            energyWatts: lead.energyWatts,
            wakeupsPerSecond: lead.wakeupsPerSecond,
            energyReadingIsPartial: lead.energyReadingIsPartial,
            wakeupReadingIsPartial: lead.wakeupReadingIsPartial,
            groupedMemberCount: memberCount,
            parentPid: lead.parentPid
        )
    }

    private static func metric(
        _ pid: Int32,
        column: ProcessSortColumn,
        rates: [Int32: ProcessEnergyRates]
    ) -> Double? {
        switch column {
        case .energy:
            return rates[pid]?.watts
        case .wakeups:
            return rates[pid]?.wakeupsPerSecond
        case .name, .cpu, .memory, .threads, .disk, .diskRead, .diskWrite:
            return nil
        }
    }
}
