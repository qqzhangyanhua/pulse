import Darwin
import SwiftUI

extension ProcessDetailSidebar {
    /// Memory page only. The title stays out of `metrics`.
    func memoryPeak(_ detail: ProcessDetail) -> some View {
        let row = memoryMagnitudeRow(fallback: displayedMemoryRow(detail.row))
        let value = MemoryPeakText.string(
            bytes: row.lifetimeMaxFootprintBytes,
            rowUid: row.userID,
            selfUid: UInt32(getuid())
        )
        return SidebarMetric(
            systemImage: "memorychip",
            title: MemoryPeakText.title,
            tint: PulsePalette.accent,
            value: value,
            caption: ""
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(MemoryPeakText.title)，\(value)")
    }
}
