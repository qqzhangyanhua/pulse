import SwiftUI

/// Full-width advice card. Not an inline caption.
struct ThermalAdviceCard: View {
    let advice: ThermalAdvice
    /// #156 wires this to the VM method that calls `ProcessActions.terminate` with no confirmation.
    let onTerminate: (Int32) -> Void

    var body: some View {
        PulseCard {
            if advice.noHighLoad {
                Text(ThermalAdvice.noHighLoadMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(advice.processes, id: \.pid) { process in
                        processRow(process)
                    }
                }
            }
        }
        // Content height: `PulseCard` would otherwise expand like a hero tile.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func processRow(_ process: ThermalAdviceProcess) -> some View {
        HStack(spacing: 8) {
            ProcessIconView(pid: process.pid, bundleIdentifier: process.bundleIdentifier, size: 16)
                .accessibilityHidden(true)
            Text(process.name)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(CPUPercentText.string(process.cpuPercent))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("退出") {
                onTerminate(process.pid)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
