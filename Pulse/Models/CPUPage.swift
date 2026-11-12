import Foundation

/// Display text for a CPU percent. Missing samples stay an em dash and are never shown as 0%.
enum CPUPercentText {
    static let missing = "—"
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func string(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%.1f%%", locale: posix, value)
    }
}

/// Calm CPU-page copy. Memory-page wording stays on the memory page.
enum CPUPageCopy {
    static let sampling = "正在采样…"
    static let emptyTitle = "还没有进程数据"
    static let emptyMessage = "这一帧没有进程可显示。"
    static let failureTitle = "暂时读不到 CPU 数据"
    static let failureMessage = SamplingRetryChrome.overviewFailureMessage
    static let retry = SamplingRetryChrome.buttonTitle
    static let sidebarEmpty = "选一个进程看详情"

    /// Resource-tab name-filter empty. The sentence stays today's pane copy.
    /// Clearing still means the name only; memory-page empties do not read these.
    static let filteredEmptyTitle = "没有匹配的 App"
    static let filteredEmptyMessage = "换个名称试试，或清空过滤。"
    static let filteredEmptyButton = "清空过滤"

    /// Overview slot. `nil` (first frame or a missed host read) is 「CPU · —」, not 「CPU · 0.0%」.
    static func overviewLine(systemCpuPercent: Double?) -> String {
        "CPU · \(CPUPercentText.string(systemCpuPercent))"
    }

    static func busiestCoreLine(percent: Double?) -> String {
        "最忙的一核 · \(CPUPercentText.string(percent))"
    }
}

enum CPUPagePhase: Equatable, Sendable {
    case sampling
    case failed
    case empty
    case filteredEmpty
    case ready
}

enum CPUPagePhaseResolver {
    static func resolve(
        loadState: LoadState,
        processCount: Int,
        visibleCount: Int,
        hasActiveFilter: Bool,
        processListFailed: Bool
    ) -> CPUPagePhase {
        if processCount == 0 {
            switch loadState {
            case .sampling:
                return .sampling
            case .failed:
                return .failed
            case .ready:
                return processListFailed ? .failed : .empty
            }
        }
        if hasActiveFilter, visibleCount == 0 {
            return .filteredEmpty
        }
        return .ready
    }
}

enum ProcessColumnTitle {
    static let name = "名称"
    static let cpu = "CPU"
    static let memory = "内存"
    static let threads = "线程"
    static let network = NetworkPageCopy.columnTitle
    static let diskRead = DiskPageCopy.readTitle
    static let diskWrite = DiskPageCopy.writeTitle
    static let energy = ProcessEnergyText.impactTitle
    static let wakeups = ProcessEnergyText.wakeTitle

    /// CPU page keeps the memory column. Energy is watts, not an Activity Monitor score.
    static let cpuPage = [name, cpu, memory, energy, wakeups, threads]

    /// Network page adds an unavailable marker column. It is not a sortable byte count.
    static let networkPage = [name, cpu, memory, network, threads]

    /// Disk page adds read / write rate columns. Missing cells are 「—」, not 「暂不可用」.
    static let diskPage = [name, cpu, memory, diskRead, diskWrite, threads]
}

enum ProcessSortColumn: Equatable, Sendable {
    case name
    case cpu
    case memory
    case threads
    case disk
    case diskRead
    case diskWrite
    case energy
    case wakeups
}

struct ProcessTableSort: Equatable, Sendable {
    var column: ProcessSortColumn
    var descending: Bool

    static func defaultSort(for page: DashboardPage) -> ProcessTableSort {
        switch page {
        case .cpu, .network:
            return ProcessTableSort(column: .cpu, descending: true)
        case .disk:
            return ProcessTableSort(column: .disk, descending: true)
        case .energy:
            return ProcessTableSort(column: .energy, descending: true)
        case .memory, .gpu, .machine:
            return ProcessTableSort(column: .memory, descending: true)
        }
    }

    /// Same click rules as the memory table: name starts ascending; the metric columns start descending.
    func selecting(_ column: ProcessSortColumn) -> ProcessTableSort {
        if self.column == column {
            return ProcessTableSort(column: column, descending: !descending)
        }
        return ProcessTableSort(column: column, descending: column != .name)
    }

    /// Primary column follows `descending`. Equal primary keys break ties by pid
    /// ascending, which is not flipped by `descending`. There is no PID column.
    func ordered(_ rows: [ProcessRow]) -> [ProcessRow] {
        rows.sorted { lhs, rhs in
            let relation = compare(lhs, rhs)
            if relation != .orderedSame {
                let lhsFirst = relation == .orderedAscending
                return descending ? !lhsFirst : lhsFirst
            }
            return lhs.pid < rhs.pid
        }
    }

    private func compare(_ lhs: ProcessRow, _ rhs: ProcessRow) -> ComparisonResult {
        switch column {
        case .name:
            return compareStrings(lhs.name, rhs.name)
        case .cpu:
            return compareDoubles(lhs.cpuSortKey, rhs.cpuSortKey)
        case .memory:
            return compareUInt(lhs.memoryBytes, rhs.memoryBytes)
        case .threads:
            if lhs.threadCount < rhs.threadCount { return .orderedAscending }
            if lhs.threadCount > rhs.threadCount { return .orderedDescending }
            return .orderedSame
        case .disk:
            return compareDoubles(lhs.diskSortKey, rhs.diskSortKey)
        case .diskRead:
            return compareDoubles(lhs.diskReadBytesPerSecond ?? -1, rhs.diskReadBytesPerSecond ?? -1)
        case .diskWrite:
            return compareDoubles(lhs.diskWriteBytesPerSecond ?? -1, rhs.diskWriteBytesPerSecond ?? -1)
        case .energy:
            return compareDoubles(lhs.energyWatts ?? -1, rhs.energyWatts ?? -1)
        case .wakeups:
            return compareDoubles(lhs.wakeupsPerSecond ?? -1, rhs.wakeupsPerSecond ?? -1)
        }
    }

    private func compareStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func compareDoubles(_ lhs: Double, _ rhs: Double) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func compareUInt(_ lhs: UInt64, _ rhs: UInt64) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}

/// View-side ring of host CPU readings. A missing percent is skipped, never stored as 0.
struct SystemCPUHistory: Equatable, Sendable {
    private(set) var samples: [ChartSample] = []
    private var nextID: UInt64 = 1
    private let limit: Int

    init(limit: Int = 90) {
        self.limit = limit
    }

    mutating func record(percent: Double?, at date: Date?) {
        guard let percent, let date else { return }
        if samples.last?.date == date { return }
        samples.append(ChartSample(id: nextID, date: date, value: percent))
        nextID += 1
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        nextID = 1
    }
}

enum ProcessNameFilter {
    static func apply(_ rows: [ProcessRow], query: String) -> [ProcessRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}

/// Main-window page plus the sort that belongs to it. Menu-bar clicks still force memory.
struct DashboardNavigation: Equatable, Sendable {
    private(set) var page: MenuBarNavigation
    private(set) var sort: ProcessTableSort

    init(page: MenuBarNavigation = MenuBarNavigation(), sort: ProcessTableSort? = nil) {
        self.page = page
        self.sort = sort ?? ProcessTableSort.defaultSort(for: page.selectedPage)
    }

    var selectedPage: DashboardPage { page.selectedPage }

    mutating func select(_ requested: DashboardPage) {
        let previous = page.selectedPage
        guard page.select(requested) else { return }
        guard previous != page.selectedPage else { return }
        sort = ProcessTableSort.defaultSort(for: page.selectedPage)
    }

    /// Lands on memory. Does not touch process selection; pair with `ProcessSelection`.
    mutating func focusMemoryPage() {
        let previous = page.selectedPage
        page.focusMemoryPage()
        guard previous != page.selectedPage else { return }
        sort = ProcessTableSort.defaultSort(for: .memory)
    }

    mutating func updateSort(_ sort: ProcessTableSort) {
        self.sort = sort
    }
}
