import Foundation

/// Memory-detail field title, share caption, and nearby help.
/// The title is shared by the metric and the main curve. Not a trend state.
struct MemoryDetailFieldCopy: Equatable, Sendable {
    let title: String
    let caption: String
    /// Static note beside the caption. Nil when the sentence already states the basis,
    /// and on every non-memory page.
    let help: String?
}

/// Page-gated memory detail copy. The memory page names footprint unless the row fell back.
/// An app-group row that includes a resident member says 「部分按驻留内存」.
/// An ungrouped resident row does not. Other pages ignore source.
/// Missing totals never call `share`.
enum MemoryDetailPresentation {
    static func field(
        page: DashboardPage,
        part: UInt64,
        total: UInt64?,
        source: ProcessMemorySource = .footprint,
        residentIsPartial: Bool = false
    ) -> MemoryDetailFieldCopy {
        let title = page == .memory
            ? (source == .footprint ? "内存占用" : "驻留内存")
            : "内存"
        guard let total, total > 0 else {
            return MemoryDetailFieldCopy(
                title: title,
                caption: "占物理内存",
                help: page == .memory ? missingTotalHelp(source, residentIsPartial: residentIsPartial) : nil
            )
        }
        let share = ByteFormat.share(part: part, total: total)
        if page == .memory {
            let basis: String
            if source == .footprint {
                basis = "按内存占用计算"
            } else if residentIsPartial {
                basis = "部分按驻留内存计算"
            } else {
                basis = "按驻留内存计算"
            }
            return MemoryDetailFieldCopy(
                title: title,
                caption: "占物理内存的 \(share)（\(basis)）",
                help: nil
            )
        }
        return MemoryDetailFieldCopy(
            title: title,
            caption: "占 \(ByteFormat.gibWhole(total)) 的 \(share)",
            help: nil
        )
    }

    private static func missingTotalHelp(
        _ source: ProcessMemorySource,
        residentIsPartial: Bool
    ) -> String {
        switch source {
        case .footprint:
            return "此数值为内存占用。当前没有物理内存总量，不显示占比。"
        case .resident:
            let lead = residentIsPartial ? "部分按驻留内存" : "按驻留内存"
            return "\(lead)。当前没有物理内存总量，不显示占比。"
        }
    }
}

/// Collapsed sampling-window copy for the live memory detail. Not a trend result.
enum MemoryDetailSamplingWindow {
    static let summary = "采样窗口与判断依据"
    static let body = "使用当前选中进程已有的采样序列，最多90点；曲线从有样本开始，无需收满。至少80点才判断上涨：首尾净增超过8 MiB，且至少60%的相邻采样间隔上涨；中间可以有下降。仅表示近期窗口，不判断异常或泄漏。"
}
