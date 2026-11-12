import Foundation

enum EnergyPagePhase: Equatable, Sendable {
    case sampling
    case processListFailed
    case sampleFailed
    case empty
    case filteredEmpty
    case ready
}

enum EnergyPageCopy {
    static let headline = "最近 1 分钟平均功率"
    static let explanation = "用这段时间里累计的能耗除以实际时长。不足 1 分钟时用已经采到的时长。读不到显示「—」，不显示 0。这不是活动监视器的能耗影响分数。"
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

/// Energy-page filter, order, and empty state. Does not read `energyWatts`.
enum EnergyPage {
    static func filtered(_ rows: [ProcessRow], query: String) -> [ProcessRow] {
        ProcessNameFilter.apply(rows, query: query)
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
