import SwiftUI

extension GPUOverviewSection {
    /// One row per active screen. The whole card is 「—」 when the read had no screens.
    var displaysCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                metricLabel(GPUDisplayCopy.title, symbol: "display.2")
                if vm.gpuDisplays.showsMissing {
                    Text(GPUDisplayCopy.missing)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(vm.gpuDisplays.rows.enumerated()), id: \.offset) { _, row in
                        displayRow(row)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displaysAccessibilityLabel)
    }

    private func displayRow(_ row: GPUDisplayRow) -> some View {
        HStack(spacing: 12) {
            Text(row.kindText)
                .frame(width: 36, alignment: .leading)
            Text(row.resolutionText)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.refreshText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var displaysAccessibilityLabel: String {
        if vm.gpuDisplays.showsMissing {
            return "\(GPUDisplayCopy.title)，\(GPUDisplayCopy.missing)"
        }
        let lines = vm.gpuDisplays.rows.map { row in
            "\(row.kindText)，\(row.resolutionText)，\(row.refreshText)"
        }
        return "\(GPUDisplayCopy.title)，\(lines.joined(separator: "；"))"
    }
}
