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

/// Page-gated memory detail copy. Memory uses the resident title and share sentence.
/// Other pages keep today's gib caption. Missing totals never call `share`.
enum MemoryDetailPresentation {
    static let missingTotalHelp = "此数值为驻留内存。当前没有物理内存总量，不显示占比。"

    static func field(page: DashboardPage, part: UInt64, total: UInt64?) -> MemoryDetailFieldCopy {
        let title = page == .memory ? "驻留内存" : "内存"
        guard let total, total > 0 else {
            return MemoryDetailFieldCopy(
                title: title,
                caption: "占物理内存",
                help: page == .memory ? missingTotalHelp : nil
            )
        }
        let share = ByteFormat.share(part: part, total: total)
        if page == .memory {
            return MemoryDetailFieldCopy(
                title: title,
                caption: "占物理内存的 \(share)（按驻留内存计算）",
                help: nil
            )
        }
        return MemoryDetailFieldCopy(
            title: title,
            caption: "占 \(ByteFormat.gibWhole(total)) 的 \(share)",
            help: nil
        )
    }
}

/// Collapsed sampling-window copy for the live memory detail. Not a trend result.
enum MemoryDetailSamplingWindow {
    static let summary = "采样窗口与判断依据"
    static let body = "使用当前选中进程已有的采样序列，最多90点；曲线从有样本开始，无需收满。至少80点才判断上涨：首尾净增超过8 MiB，且至少60%的相邻采样间隔上涨；中间可以有下降。仅表示近期窗口，不判断异常或泄漏。"
}
