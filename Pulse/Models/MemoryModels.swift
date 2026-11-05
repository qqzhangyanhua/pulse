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
}

struct ProcessRow: Identifiable, Sendable, Hashable {
    var id: Int32 { pid }

    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let executablePath: String?
    let cpuPercent: Double?
    let memoryBytes: UInt64
    let threadCount: Int

    /// Missing first-sample CPU sorts below real values without pretending it is 0%.
    var cpuSortKey: Double { cpuPercent ?? -1 }

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
    /// Host inbound/outbound rates for this tick. Nil insides on first frame, failure, or wrap.
    let hostNetworkRates: HostNetworkRates
}
