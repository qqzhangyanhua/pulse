import SwiftUI

/// Name-side capsule. The row label speaks the title; this button only runs the action.
struct ProcessRowStatusMark: View {
    var title: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityHidden(true)
    }
}

/// Name-side mark. The row label speaks it; this button only continues the process.
struct PausedProcessMark: View {
    var resume: () -> Void

    var body: some View {
        ProcessRowStatusMark(title: "已暂停", help: "继续", action: resume)
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
