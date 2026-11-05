import SwiftUI

/// Strip B shell. Three slots, single column, secondary type. Live pressure + Top3 come later.
struct MenuBarPopoverView: View {
    var onOpenPulse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MenuBarPopoverShell.sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 {
                    Divider()
                        .overlay(PulsePalette.hairline)
                }
                slot(section)
            }
        }
        .padding(12)
        .frame(width: 248, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(PulsePalette.windowBackground)
    }

    @ViewBuilder
    private func slot(_ section: MenuBarPopoverSection) -> some View {
        switch section {
        case .hostPressure:
            Text(MenuBarPopoverShell.placeholder(for: .hostPressure))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("主机压力")
                .accessibilityValue(MenuBarPopoverShell.placeholder(for: .hostPressure))
        case .topProcesses:
            Text(MenuBarPopoverShell.placeholder(for: .topProcesses))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("占用最多的进程")
                .accessibilityValue(MenuBarPopoverShell.placeholder(for: .topProcesses))
        case .openPulse:
            Button(action: onOpenPulse) {
                Text(MenuBarCopy.openPulseTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MenuBarCopy.openPulseTitle)
        }
    }
}
