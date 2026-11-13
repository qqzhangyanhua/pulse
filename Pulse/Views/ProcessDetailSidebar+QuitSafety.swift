import SwiftUI

extension ProcessDetailSidebar {
    /// No glossary entry means no row. The lookup stays out of other surfaces.
    @ViewBuilder
    func quitSafetyJudgment(for name: String) -> some View {
        if let entry = ProcessGlossary.entry(for: name) {
            Text(entry.quitSafetyText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
