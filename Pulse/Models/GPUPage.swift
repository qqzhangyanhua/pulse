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
    /// Registry `gpu-core-count` on this accelerator. Nil when that key was not a positive whole number.
    var coreCount: Int?

    init(
        statistics: [String: GPUStatistic] = [:],
        ioReportDevicePercent: Double? = nil,
        coreCount: Int? = nil
    ) {
        self.statistics = statistics
        self.ioReportDevicePercent = ioReportDevicePercent
        self.coreCount = coreCount
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
    /// Selected node's allocated system memory. Nil when that value is not a byte count.
    var allocatedMemoryBytes: UInt64?
    /// Recommended working set for this successful frame. Nil when the reader returned none.
    var recommendedMaxWorkingSetBytes: UInt64?
    var coreCount: Int?
    /// Selected node's renderer percent. Not part of utilization or the curve.
    var rendererPercent: Double?
    /// Selected node's tiler percent. Not part of utilization or the curve.
    var tilerPercent: Double?
    /// Selected node's non-negative recovery count. Nil when it is not an integer.
    var recoveryCount: Int?
    var history: SystemCPUHistory
    /// Live power points for this GPU-page visit. Not the utilization curve, and not history.
    var powerSparkline = SystemCPUHistory()
    /// Live frequency points in hertz. Idle is absent, not 0.
    var frequencySparkline = SystemCPUHistory()
    var visitSucceeded: Bool
    var chrome: GPUPageChrome

    var utilizationText: String { CPUPercentText.string(utilizationPercent) }

    var rendererText: String { CPUPercentText.string(rendererPercent) }

    var tilerText: String { CPUPercentText.string(tilerPercent) }

    var recoveryText: String {
        guard let recoveryCount else { return CPUPercentText.missing }
        return "\(recoveryCount) 次"
    }

    /// Hidden when the registry key is missing. Not a dash.
    var coreCountText: String? {
        guard let coreCount, coreCount > 0 else { return nil }
        return GPUPageCopy.coreCountLine(coreCount)
    }

    var memoryText: String {
        guard let inUseMemoryBytes else { return CPUPercentText.missing }
        return ByteFormat.memory(inUseMemoryBytes)
    }

    var allocatedText: String {
        guard let allocatedMemoryBytes else { return CPUPercentText.missing }
        return ByteFormat.memory(allocatedMemoryBytes)
    }

    var recommendedLimitText: String {
        guard let recommendedMaxWorkingSetBytes else { return CPUPercentText.missing }
        return ByteFormat.memory(recommendedMaxWorkingSetBytes)
    }

    /// Nil when either byte count is missing. A ratio above 1 draws full; the texts stay real.
    var memoryBarFraction: Double? {
        guard let used = inUseMemoryBytes, let limit = recommendedMaxWorkingSetBytes else { return nil }
        if limit == 0 { return used == 0 ? 0 : 1 }
        return min(1, Double(used) / Double(limit))
    }

    /// Fewer than two points is not a line.
    var showsCurve: Bool { history.samples.count >= 2 }

    /// Fewer than two power points is not a line.
    var showsPowerSparkline: Bool { powerSparkline.samples.count >= 2 }

    /// Fewer than two frequency points is not a line.
    var showsFrequencySparkline: Bool { frequencySparkline.samples.count >= 2 }

    var powerSparklineDomain: ClosedRange<Double> {
        GPULiveSparkline.domain(powerSparkline.samples.map(\.value))
    }

    var frequencySparklineDomain: ClosedRange<Double> {
        GPULiveSparkline.domain(frequencySparkline.samples.map(\.value))
    }

    static let initial = GPUPageState(
        utilizationPercent: nil,
        inUseMemoryBytes: nil,
        allocatedMemoryBytes: nil,
        recommendedMaxWorkingSetBytes: nil,
        coreCount: nil,
        rendererPercent: nil,
        tilerPercent: nil,
        recoveryCount: nil,
        history: SystemCPUHistory(),
        visitSucceeded: false,
        chrome: .skeleton
    )
}

/// Points drawn on the power and frequency cards. Missing and idle are not points.
enum GPULiveSparkline {
    /// Finite watts, including a real 0. Nil and non-finite stay off the line.
    static func watts(_ watts: Double?) -> Double? {
        guard let watts, watts.isFinite else { return nil }
        return watts
    }

    /// Working hertz, including a real 0. Idle and missing are not 0 Hz.
    static func hertz(_ frequency: GPUFrequency) -> Double? {
        guard case .hertz(let hertz) = frequency, hertz.isFinite, hertz >= 0 else { return nil }
        return hertz
    }

    /// Sample span, with a pad that stays visible for both watts and hertz.
    static func domain(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let span = high - low
        let pad = max(span * 0.25, max(abs(high), abs(low), 1) * 0.08)
        return (low - pad)...(high + pad)
    }
}

enum GPUPageCopy {
    static let utilization = "GPU 使用率"
    static let renderer = "渲染器"
    static let tiler = "分块器"
    static let recovery = "GPU 恢复次数"
    static let recoveryCaption = "GPU 卡住后，驱动重置它的次数"
    static let memory = "GPU 占用内存"
    static let allocated = "已分配"
    static let recommendedLimit = "建议上限"
    static let power = "GPU 功耗"
    static let frequency = "GPU 频率"
    static let sampling = "正在采样…"
    static let failureTitle = "暂时读不到 GPU 数据"
    static let failureMessage = SamplingRetryChrome.overviewFailureMessage
    static let chartCollecting = "曲线采集中"

    static func coreCountLine(_ count: Int) -> String {
        "\(count) 核 GPU"
    }

    static func recommendedLimitLine(_ value: String) -> String {
        "\(recommendedLimit) \(value)"
    }
}

enum GPUCoreCount {
    static let registryKey = "gpu-core-count"

    /// A positive whole number from the registry. Anything else stays missing.
    static func parse(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0, value <= Double(Int.max), value == value.rounded() else {
            return nil
        }
        return Int(value)
    }

    /// First positive count in input order. Counts are not summed.
    static func first(in nodes: [GPUAcceleratorNode]) -> Int? {
        for node in nodes {
            if let count = node.coreCount, count > 0 {
                return count
            }
        }
        return nil
    }
}

enum GPUPageProjection {
    static let deviceUtilizationKey = "Device Utilization %"
    static let rendererUtilizationKey = "Renderer Utilization %"
    static let tilerUtilizationKey = "Tiler Utilization %"
    static let recoveryCountKey = "recoveryCount"
    static let inUseSystemMemoryKey = "In use system memory"
    static let allocSystemMemoryKey = "Alloc system memory"

    static func apply(
        nodes: [GPUAcceleratorNode] = [],
        recommendedMaxWorkingSetBytes: UInt64? = nil,
        frame: GPUFrameOutcome,
        sampledAt: Date?,
        current: GPUPageState,
        transition: GPUPageTransition
    ) -> GPUPageState {
        // The curve lives for the process. Leave does not clear it, and enter keeps it.
        switch transition {
        case .justLeft:
            return current
        case .justEntered, .stayed:
            return applyFrame(
                frame,
                nodes: nodes,
                recommendedMaxWorkingSetBytes: recommendedMaxWorkingSetBytes,
                sampledAt: sampledAt,
                to: current
            )
        }
    }

    private static func applyFrame(
        _ frame: GPUFrameOutcome,
        nodes: [GPUAcceleratorNode],
        recommendedMaxWorkingSetBytes: UInt64?,
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
            next.allocatedMemoryBytes = reading.allocated
            next.recommendedMaxWorkingSetBytes = recommendedMaxWorkingSetBytes
            next.rendererPercent = reading.renderer
            next.tilerPercent = reading.tiler
            next.recoveryCount = reading.recovery
            next.coreCount = GPUCoreCount.first(in: nodes)
            next.visitSucceeded = true
            next.chrome = .readings
            next.history.record(percent: reading.utilization, at: sampledAt)
            return next
        }
    }

    private struct ChosenReading {
        var utilization: Double?
        var memory: UInt64?
        var allocated: UInt64?
        var renderer: Double?
        var tiler: Double?
        var recovery: Int?
    }

    /// Nodes that have in-use memory win, even when the value is not a byte count.
    /// Otherwise the first in-range device percent wins. A present device key
    /// that is out of range is not eligible and does not use the device channel.
    /// Renderer, tiler, recovery, and allocated bytes come from that same node.
    private static func reading(from nodes: [GPUAcceleratorNode]) -> ChosenReading {
        guard let node = chosenNode(in: nodes) else {
            return ChosenReading(
                utilization: nil,
                memory: nil,
                allocated: nil,
                renderer: nil,
                tiler: nil,
                recovery: nil
            )
        }
        return ChosenReading(
            utilization: utilization(on: node),
            memory: memoryBytes(on: node),
            allocated: allocatedBytes(on: node),
            renderer: percent(node.statistics[rendererUtilizationKey]),
            tiler: percent(node.statistics[tilerUtilizationKey]),
            recovery: recoveryCount(on: node)
        )
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

    private static func percent(_ statistic: GPUStatistic?) -> Double? {
        switch statistic {
        case .number(let number):
            return percent(number)
        case .bytes(let bytes):
            return percent(Double(bytes))
        case .unreadable, nil:
            return nil
        }
    }

    /// A non-negative whole number. A fraction, a sign, or a non-finite value stays missing.
    private static func recoveryCount(on node: GPUAcceleratorNode) -> Int? {
        guard case .number(let number) = node.statistics[recoveryCountKey] else { return nil }
        guard number.isFinite, number >= 0, number < Double(Int.max), number == number.rounded() else {
            return nil
        }
        return Int(number)
    }

    private static func percent(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 100 else { return nil }
        return value
    }

    private static func memoryBytes(on node: GPUAcceleratorNode) -> UInt64? {
        guard case .bytes(let bytes) = node.statistics[inUseSystemMemoryKey] else { return nil }
        return bytes
    }

    /// Another node's allocated bytes are not borrowed when this one is not a byte count.
    private static func allocatedBytes(on node: GPUAcceleratorNode) -> UInt64? {
        guard case .bytes(let bytes) = node.statistics[allocSystemMemoryKey] else { return nil }
        return bytes
    }
}

/// Mean and peak texts for the utilization curve. Both are 「—」 when no number qualifies.
struct GPUCurveSummary: Equatable, Sendable {
    var meanText: String
    var peakText: String

    static let meanTitle = "均值"
    static let peakTitle = "峰值"
}

extension GPUPageState {
    /// 「实时」 uses the in-memory ring. Other ranges use history points.
    /// A nil point is a gap, not 0. No finite number is 「—」.
    func curveSummary(range: HistoryCurveRange, historyPoints: [Double?]) -> GPUCurveSummary {
        let numbers = range == .live ? finiteLiveSamples : finiteHistoryPoints(historyPoints)
        guard !numbers.isEmpty, let peak = numbers.max() else {
            return GPUCurveSummary(meanText: CPUPercentText.missing, peakText: CPUPercentText.missing)
        }
        let mean = numbers.reduce(0, +) / Double(numbers.count)
        return GPUCurveSummary(
            meanText: CPUPercentText.string(mean),
            peakText: CPUPercentText.string(peak)
        )
    }

    private var finiteLiveSamples: [Double] {
        history.samples.map(\.value).filter(\.isFinite)
    }

    private func finiteHistoryPoints(_ points: [Double?]) -> [Double] {
        points.compactMap { point in
            guard let point, point.isFinite else { return nil }
            return point
        }
    }
}
