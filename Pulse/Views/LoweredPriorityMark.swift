import SwiftUI

/// Name-side mark. The row label speaks it; this button only restores priority.
struct LoweredPriorityMark: View {
    var restore: () -> Void

    var body: some View {
        ProcessRowStatusMark(title: "已降低优先级", help: "恢复优先级", action: restore)
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
