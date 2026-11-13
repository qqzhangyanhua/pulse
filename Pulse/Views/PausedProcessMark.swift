import SwiftUI

/// Name-side mark. The row label speaks it; this button only continues the process.
struct PausedProcessMark: View {
    var resume: () -> Void

    var body: some View {
        Button(action: resume) {
            Text("已暂停")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("继续")
        .accessibilityHidden(true)
    }
}

struct PauseResumeAction: ViewModifier {
    var enabled: Bool
    var resume: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: "继续") { resume() }
        } else {
            content
        }
    }
}
