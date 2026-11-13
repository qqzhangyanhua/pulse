import SwiftUI

/// Name-side mark. The row label speaks it; this button only restores priority.
struct LoweredPriorityMark: View {
    var restore: () -> Void

    var body: some View {
        Button(action: restore) {
            Text("已降低优先级")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("恢复优先级")
        .accessibilityHidden(true)
    }
}

struct PriorityRestoreAction: ViewModifier {
    var enabled: Bool
    var restore: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: "恢复优先级") { restore() }
        } else {
            content
        }
    }
}
