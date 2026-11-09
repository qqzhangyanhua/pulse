import Foundation

/// Visible attribution for the memory-page detail frame already on screen.
/// Other pages stay empty. The caller passes whether the slot is rising;
/// this type does not sample, group, or evaluate a series.
struct MemoryDetailAttribution: Equatable, Sendable {
    /// Sentence under the share caption. Nil off the memory page.
    let magnitude: String?
    /// Curve title from the curve row's own source. Nil off the memory page.
    let curveTitle: String?
    /// "PID n" once the memory curve has at least two points.
    /// Nil for zero or one point, and off the memory page.
    let curvePid: String?
    /// Rising slot only. Nil when that slot is absent or not rising.
    let trend: String?

    static let curvePlaceholder = "正在采集内存曲线"

    static func make(
        page: DashboardPage,
        magnitudeRow: ProcessRow,
        curveRow: ProcessRow,
        memoryPointCount: Int,
        trendIsRising: Bool
    ) -> MemoryDetailAttribution {
        guard page == .memory else {
            return MemoryDetailAttribution(magnitude: nil, curveTitle: nil, curvePid: nil, trend: nil)
        }
        let magnitude: String
        if let count = magnitudeRow.groupedMemberCount {
            magnitude = "当前可见的 \(count) 个同名进程合计"
        } else {
            magnitude = "当前进程（PID \(magnitudeRow.pid)）"
        }
        let curveTitle = curveRow.memorySource == .footprint ? "内存占用" : "驻留内存"
        let curvePid = memoryPointCount >= 2 ? "PID \(curveRow.pid)" : nil
        let trend = trendIsRising ? "这条趋势属于 PID \(curveRow.pid)" : nil
        return MemoryDetailAttribution(
            magnitude: magnitude,
            curveTitle: curveTitle,
            curvePid: curvePid,
            trend: trend
        )
    }

    /// Puts the pid in front of an already formatted recent/peak sentence.
    /// A missing pid line leaves that sentence unchanged. Memory-page blanking for
    /// fewer than two points is `curveSummary(page:samples:curvePid:)`.
    static func curveSummary(pidLine: String?, recentAndPeak: String) -> String {
        guard let pidLine, !recentAndPeak.isEmpty else { return recentAndPeak }
        return "\(pidLine) · \(recentAndPeak)"
    }

    /// Latest sample and the max, same sentence the chart used before attribution.
    /// One sample still has both, so this string is not itself the memory-page summary.
    static func recentAndPeak(_ samples: [ChartSample]) -> String {
        guard let latest = samples.last?.value, let peak = samples.map(\.value).max() else { return "" }
        return "最近 \(ByteFormat.memory(UInt64(max(0, latest)))) · 峰值 \(ByteFormat.memory(UInt64(max(0, peak))))"
    }

    /// Memory page hides the summary until two points exist. Other pages keep it.
    static func curveSummary(page: DashboardPage, samples: [ChartSample], curvePid: Int32) -> String {
        let sentence = recentAndPeak(samples)
        guard page == .memory else { return sentence }
        guard samples.count >= 2 else { return "" }
        return curveSummary(pidLine: "PID \(curvePid)", recentAndPeak: sentence)
    }
}
