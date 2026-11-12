import Foundation

enum PressureLevel: String, Sendable, Equatable {
    case normal
    case elevated

    var title: String {
        switch self {
        case .normal: return "正常"
        case .elevated: return "偏高"
        }
    }

    var caption: String {
        switch self {
        case .normal:
            return "余量充足"
        case .elevated:
            return "余量紧张"
        }
    }
}

struct ChartSample: Identifiable, Sendable, Equatable, Hashable {
    let id: UInt64
    let date: Date
    let value: Double
}

struct MemoryBreakdown: Sendable, Equatable {
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64

    var usedBytes: UInt64 {
        appBytes &+ wiredBytes &+ compressedBytes
    }

    var categorizedBytes: UInt64 {
        usedBytes &+ cachedBytes
    }
}

struct UsageHistory: Equatable, Sendable {
    private(set) var samples: [ChartSample] = []
    private var nextID: UInt64 = 1
    private let limit = 90

    mutating func record(_ snapshot: MemorySnapshot?) {
        guard let snapshot else {
            samples.removeAll(keepingCapacity: true)
            return
        }
        if samples.last?.date == snapshot.capturedAt {
            return
        }
        samples.append(
            ChartSample(id: nextID, date: snapshot.capturedAt, value: Double(snapshot.usedBytes))
        )
        nextID += 1
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }
}

struct MemorySnapshot: Sendable, Equatable {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let breakdown: MemoryBreakdown
    let pressure: PressureLevel
    let pressureMetric: Double
    let pressureSeries: [ChartSample]
    let capturedAt: Date
    /// `vm.swapusage` used bytes. Nil is an unread sample. Zero is a real empty swap file.
    let swapUsedBytes: UInt64?

    init(
        usedBytes: UInt64,
        totalBytes: UInt64,
        breakdown: MemoryBreakdown,
        pressure: PressureLevel,
        pressureMetric: Double,
        pressureSeries: [ChartSample],
        capturedAt: Date,
        swapUsedBytes: UInt64? = nil
    ) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.breakdown = breakdown
        self.pressure = pressure
        self.pressureMetric = pressureMetric
        self.pressureSeries = pressureSeries
        self.capturedAt = capturedAt
        self.swapUsedBytes = swapUsedBytes
    }
}

struct ProcessRow: Identifiable, Sendable, Hashable {
    var id: Int32 { pid }

    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let executablePath: String?
    let cpuPercent: Double?
    let memoryBytes: UInt64
    /// `footprint` unless that read was nil. Call sites that omit it stay on footprint.
    let memorySource: ProcessMemorySource
    /// App-group row that includes a resident member, including a one-member group.
    /// An ungrouped row stays false.
    let residentMemoryIsPartial: Bool
    let threadCount: Int
    /// `proc_pid_rusage` two-frame rates. Nil on first frame, EPERM, wrap, or a failed read.
    let diskReadBytesPerSecond: Double?
    let diskWriteBytesPerSecond: Double?
    /// Watts from `ri_energy_nj`. Nil on first frame, a decreased counter, or a failed read.
    let energyWatts: Double?
    /// `ri_interrupt_wkups` per second. Nil on the same frames as `energyWatts`.
    let wakeupsPerSecond: Double?
    /// App-group row whose energy sum skipped a nil member. An ungrouped row stays false.
    let energyReadingIsPartial: Bool
    /// App-group row whose wakeup sum skipped a nil member. An ungrouped row stays false.
    let wakeupReadingIsPartial: Bool
    /// Nil on an ungrouped row. A grouped row stores `members.count`, including 1.
    let groupedMemberCount: Int?
    /// `PROC_PIDTBSDINFO` parent. Nil when that read fails. Zero is a real ppid, not a failure.
    let parentPid: Int32?

    init(
        pid: Int32,
        name: String,
        bundleIdentifier: String?,
        executablePath: String?,
        cpuPercent: Double?,
        memoryBytes: UInt64,
        memorySource: ProcessMemorySource = .footprint,
        residentMemoryIsPartial: Bool = false,
        threadCount: Int,
        diskReadBytesPerSecond: Double? = nil,
        diskWriteBytesPerSecond: Double? = nil,
        energyWatts: Double? = nil,
        wakeupsPerSecond: Double? = nil,
        energyReadingIsPartial: Bool = false,
        wakeupReadingIsPartial: Bool = false,
        groupedMemberCount: Int? = nil,
        parentPid: Int32? = nil
    ) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = executablePath
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.memorySource = memorySource
        self.residentMemoryIsPartial = residentMemoryIsPartial
        self.threadCount = threadCount
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.energyWatts = energyWatts
        self.wakeupsPerSecond = wakeupsPerSecond
        self.energyReadingIsPartial = energyReadingIsPartial
        self.wakeupReadingIsPartial = wakeupReadingIsPartial
        self.groupedMemberCount = groupedMemberCount
        self.parentPid = parentPid
    }

    /// Missing first-sample CPU sorts below real values without pretending it is 0%.
    var cpuSortKey: Double { cpuPercent ?? -1 }

    /// Combined disk rate for later tab sort. Missing values sink below a real 0 B/s.
    var diskSortKey: Double {
        guard let diskReadBytesPerSecond, let diskWriteBytesPerSecond else { return -1 }
        return diskReadBytesPerSecond + diskWriteBytesPerSecond
    }

    /// Per-process bytes are not available from `PROC_PIDTASKINFO`. Never a fabricated count.
    var networkAvailability: ProcessNetworkAvailability { .unavailable }
}

/// Process-level network has no public byte source without entitlements / private APIs.
enum ProcessNetworkAvailability: Sendable, Equatable {
    case unavailable

    /// UI later shows this marker. Not an em dash and not `0 B/s`.
    var label: String {
        switch self {
        case .unavailable:
            return "暂不可用"
        }
    }
}

struct ProcessDetail: Sendable, Equatable {
    let row: ProcessRow
    let memorySeries: [ChartSample]
    let cpuSeries: [ChartSample]
}

enum LoadState: Equatable {
    case sampling
    case ready
    case failed
}

enum QuitPhase: Equatable {
    case idle
    case quitting
    case failed
}

enum ProcessActionResult: Equatable {
    case exited
    case notFound
    case requestFailed
    case stillRunning
}

struct SampledFrame: Sendable {
    let snapshot: MemorySnapshot
    let rows: [ProcessRow]
    let detail: ProcessDetail?
    let processListFailed: Bool
    /// Host CPU for this tick. Nil on the first sample or when the host read fails.
    let systemCpuPercent: Double?
    /// Busiest core this tick. Nil is missing, not zero: first frame, missed per-core read, or a core-count change.
    let busiestCorePercent: Double?
    /// Host inbound/outbound rates for this tick. Nil insides on first frame, failure, or wrap.
    let hostNetworkRates: HostNetworkRates
    /// Host disk read/write rates for this tick. Nil insides on first frame, failure, or wrap.
    let hostDiskRates: HostDiskRates
    /// Bounded Top N=5 memory series for this tick. Empty when the process list failed.
    let topMemorySeries: [Int32: [ChartSample]]
    /// This frame only. Nil when the list failed or no task-info read was denied.
    let permissionFootnote: String?
    /// Energy-page window rates for this frame. Empty when the process list failed.
    let energyWindowRates: [Int32: ProcessEnergyRates]
    /// Energy-page hour rates from the minute ledger. Empty when the process list failed.
    let energyHourRates: [Int32: ProcessEnergyRates]
    /// Sealed hour generations. Empty when the process list failed. Not inside `energyHourRates`.
    let exitedEnergyProcesses: [ExitedEnergyProcess]

    init(
        snapshot: MemorySnapshot,
        rows: [ProcessRow],
        detail: ProcessDetail?,
        processListFailed: Bool,
        systemCpuPercent: Double?,
        hostNetworkRates: HostNetworkRates,
        hostDiskRates: HostDiskRates,
        topMemorySeries: [Int32: [ChartSample]] = [:],
        busiestCorePercent: Double? = nil,
        permissionFootnote: String? = nil,
        energyWindowRates: [Int32: ProcessEnergyRates] = [:],
        energyHourRates: [Int32: ProcessEnergyRates] = [:],
        exitedEnergyProcesses: [ExitedEnergyProcess] = []
    ) {
        self.snapshot = snapshot
        self.rows = rows
        self.detail = detail
        self.processListFailed = processListFailed
        self.systemCpuPercent = systemCpuPercent
        self.hostNetworkRates = hostNetworkRates
        self.hostDiskRates = hostDiskRates
        self.topMemorySeries = topMemorySeries
        self.busiestCorePercent = busiestCorePercent
        self.permissionFootnote = permissionFootnote
        self.energyWindowRates = energyWindowRates
        self.energyHourRates = energyHourRates
        self.exitedEnergyProcesses = exitedEnergyProcesses
    }
}
