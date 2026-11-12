import Foundation

/// One value from an accelerator's published performance statistics.
enum GPUStatistic: Equatable, Sendable {
    /// A byte count. Real 0 is a byte count.
    case bytes(UInt64)
    /// A numeric reading, including non-finite percents.
    case number(Double)
    /// The key is present, but the value is not a byte count or a number.
    case unreadable
}

/// One accelerator node, in the order the adapter enumerated it.
struct GPUAcceleratorNode: Equatable, Sendable {
    var statistics: [String: GPUStatistic]
    /// Same-node device-channel percent. Nil when that channel was not read.
    var ioReportDevicePercent: Double?

    init(
        statistics: [String: GPUStatistic] = [:],
        ioReportDevicePercent: Double? = nil
    ) {
        self.statistics = statistics
        self.ioReportDevicePercent = ioReportDevicePercent
    }
}

enum GPUFrameOutcome: Equatable, Sendable {
    case pending
    case failed
    case succeeded
}

enum GPUPageTransition: Equatable, Sendable {
    case stayed
    case justLeft
    case justEntered
}

enum GPUPageChrome: Equatable, Sendable {
    /// This visit's first frame has not come back.
    case skeleton
    /// This visit has no successful frame, and the latest frame failed.
    case samplingFailure
    /// Numbers are published. A missing key is 「—」, not a hidden card.
    case readings
}

/// GPU page readings and the one utilization curve. Memory has no curve.
struct GPUPageState: Equatable, Sendable {
    var utilizationPercent: Double?
    var inUseMemoryBytes: UInt64?
    var history: SystemCPUHistory
    var visitSucceeded: Bool
    var chrome: GPUPageChrome

    var utilizationText: String { CPUPercentText.string(utilizationPercent) }

    var memoryText: String {
        guard let inUseMemoryBytes else { return CPUPercentText.missing }
        return ByteFormat.memory(inUseMemoryBytes)
    }

    /// Fewer than two points is not a line.
    var showsCurve: Bool { history.samples.count >= 2 }

    static let initial = GPUPageState(
        utilizationPercent: nil,
        inUseMemoryBytes: nil,
        history: SystemCPUHistory(),
        visitSucceeded: false,
        chrome: .skeleton
    )
}

enum GPUPageCopy {
    static let utilization = "GPU 使用率"
    static let memory = "GPU 占用内存"
    static let sampling = "正在采样…"
    static let failureTitle = "暂时读不到 GPU 数据"
    static let failureMessage = SamplingRetryChrome.overviewFailureMessage
    static let chartCollecting = "曲线采集中"
}

enum GPUPageProjection {
    static let deviceUtilizationKey = "Device Utilization %"
    static let inUseSystemMemoryKey = "In use system memory"

    static func apply(
        nodes: [GPUAcceleratorNode] = [],
        frame: GPUFrameOutcome,
        sampledAt: Date?,
        current: GPUPageState,
        transition: GPUPageTransition
    ) -> GPUPageState {
        switch transition {
        case .justLeft:
            var next = current
            next.history.reset()
            return next
        case .justEntered:
            return applyFrame(frame, nodes: nodes, sampledAt: sampledAt, to: .initial)
        case .stayed:
            return applyFrame(frame, nodes: nodes, sampledAt: sampledAt, to: current)
        }
    }

    private static func applyFrame(
        _ frame: GPUFrameOutcome,
        nodes: [GPUAcceleratorNode],
        sampledAt: Date?,
        to current: GPUPageState
    ) -> GPUPageState {
        switch frame {
        case .pending:
            var next = current
            next.chrome = current.visitSucceeded ? .readings : .skeleton
            return next
        case .failed:
            guard current.visitSucceeded else {
                var next = current
                next.chrome = .samplingFailure
                return next
            }
            var next = current
            next.chrome = .readings
            return next
        case .succeeded:
            let reading = reading(from: nodes)
            var next = current
            next.utilizationPercent = reading.utilization
            next.inUseMemoryBytes = reading.memory
            next.visitSucceeded = true
            next.chrome = .readings
            next.history.record(percent: reading.utilization, at: sampledAt)
            return next
        }
    }

    /// Nodes that have in-use memory win, even when the value is not a byte count.
    /// Otherwise the first in-range device percent wins. A present device key
    /// that is out of range is not eligible and does not use the device channel.
    /// Nothing is summed.
    private static func reading(from nodes: [GPUAcceleratorNode]) -> (utilization: Double?, memory: UInt64?) {
        guard let node = chosenNode(in: nodes) else { return (nil, nil) }
        return (utilization(on: node), memoryBytes(on: node))
    }

    private static func chosenNode(in nodes: [GPUAcceleratorNode]) -> GPUAcceleratorNode? {
        var firstWithMemoryKey: GPUAcceleratorNode?
        var bestBytesNode: GPUAcceleratorNode?
        var bestBytes: UInt64 = 0
        for node in nodes {
            guard node.statistics[inUseSystemMemoryKey] != nil else { continue }
            if firstWithMemoryKey == nil { firstWithMemoryKey = node }
            guard case .bytes(let bytes) = node.statistics[inUseSystemMemoryKey] else { continue }
            if bestBytesNode == nil || bytes > bestBytes {
                bestBytes = bytes
                bestBytesNode = node
            }
        }
        if let bestBytesNode { return bestBytesNode }
        if let firstWithMemoryKey { return firstWithMemoryKey }
        return nodes.first { utilization(on: $0) != nil }
    }

    /// A present device key blocks the device channel, even when it cannot be used.
    private static func utilization(on node: GPUAcceleratorNode) -> Double? {
        if let statistic = node.statistics[deviceUtilizationKey] {
            return percent(statistic)
        }
        return percent(node.ioReportDevicePercent)
    }

    private static func percent(_ statistic: GPUStatistic) -> Double? {
        switch statistic {
        case .number(let number):
            return percent(number)
        case .bytes(let bytes):
            return percent(Double(bytes))
        case .unreadable:
            return nil
        }
    }

    private static func percent(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 100 else { return nil }
        return value
    }

    private static func memoryBytes(on node: GPUAcceleratorNode) -> UInt64? {
        guard case .bytes(let bytes) = node.statistics[inUseSystemMemoryKey] else { return nil }
        return bytes
    }
}
