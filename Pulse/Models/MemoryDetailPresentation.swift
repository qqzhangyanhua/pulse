import Foundation

/// Memory-detail field title, share caption, and nearby help.
/// The title is shared by the metric and the main curve. Not a trend state.
struct MemoryDetailFieldCopy: Equatable, Sendable {
    let title: String
    let caption: String
    let help: String?
}

/// Page-gated memory detail copy. The pre-lock body still emits today's
/// shared 「内存」 title and the gib share sentence, so the resident locks fail.
enum MemoryDetailPresentation {
    static func field(page: DashboardPage, part: UInt64, total: UInt64?) -> MemoryDetailFieldCopy {
        _ = page
        if let total, total > 0 {
            return MemoryDetailFieldCopy(
                title: "内存",
                caption: "占 \(ByteFormat.gibWhole(total)) 的 \(ByteFormat.share(part: part, total: total))",
                help: nil
            )
        }
        return MemoryDetailFieldCopy(title: "内存", caption: "占物理内存", help: nil)
    }
}

/// Sampling-window disclosure copy. Empty until the locked sentences land.
enum MemoryDetailSamplingWindow {
    static let summary = ""
    static let body = ""
}
