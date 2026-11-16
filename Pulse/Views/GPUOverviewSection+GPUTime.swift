import SwiftUI

extension GPUOverviewSection {
    /// Hour ranking. An empty ledger is 「—」, not a missing card.
    var gpuTimeCard: some View {
        card(vm.gpuTime)
    }

    private func card(_ gpuTime: GPUTimePresentation?) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(GPUTimeCopy.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let rows = gpuTime?.rows, !rows.isEmpty {
                    ForEach(rows) { row in
                        timeRow(row)
                    }
                } else {
                    Text(CPUPercentText.missing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func timeRow(_ row: GPUTimeRow) -> some View {
        HStack(spacing: 8) {
            ProcessIconView(pid: row.pid, bundleIdentifier: nil, size: 16)
                .accessibilityHidden(true)
            Text(row.name)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.exited {
                Text(GPUTimeCopy.exited)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(row.secondsText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(timeLabel(row))
    }

    private func timeLabel(_ row: GPUTimeRow) -> String {
        var parts = [row.name]
        if row.exited {
            parts.append(GPUTimeCopy.exited)
        }
        parts.append("\(GPUTimeCopy.title) \(row.secondsText)")
        return parts.joined(separator: "，")
    }
}
