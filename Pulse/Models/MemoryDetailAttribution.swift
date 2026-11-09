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

    /// Puts the pid in front of the existing recent/peak sentence.
    /// No pid line, or an empty recent/peak sentence, leaves that sentence unchanged.
    static func curveSummary(pidLine: String?, recentAndPeak: String) -> String {
        guard let pidLine, !recentAndPeak.isEmpty else { return recentAndPeak }
        return "\(pidLine) · \(recentAndPeak)"
    }
}
