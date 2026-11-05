import SwiftUI

/// Strip B. Three peer slots, single column, secondary type. Host pressure and
/// used memory share one information block. Live values are a read-only
/// projection of the same dashboard the color-dot and main window use.
struct MenuBarPopoverView: View {
    @ObservedObject var dashboard: MemoryDashboardVM
    var onOpenPulse: () -> Void
    var onSelectProcess: (Int32) -> Void

    private var strip: MenuBarPopoverSnapshot {
        dashboard.menuBarPopover
    }

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
            VStack(alignment: .leading, spacing: 4) {
                Text(strip.pressureLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("主机压力")
                    .accessibilityValue(strip.pressureLine)
                Text(strip.usedMemoryLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("已用内存")
                    .accessibilityValue(strip.usedMemoryLine)
            }
        case .topProcesses:
            topProcessesSlot
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

    @ViewBuilder
    private var topProcessesSlot: some View {
        if let empty = strip.processesEmptyCopy {
            Text(empty)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("占用最多的进程")
                .accessibilityValue(empty)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(strip.processes) { process in
                    Button {
                        onSelectProcess(process.pid)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(process.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 8)
                            Text(ByteFormat.memory(process.memoryBytes))
                                .monospacedDigit()
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(process.name)
                    .accessibilityValue(ByteFormat.memory(process.memoryBytes))
                    .accessibilityAddTraits(.isButton)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("占用最多的进程")
        }
    }
}
