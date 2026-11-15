import SwiftUI

extension GPUOverviewSection {
    /// One bar per frequency state. Missing sample delta is 「—」, not a zero bar.
    var frequencyDistributionCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(GPUFrequencyDistributionCopy.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                switch vm.gpuFrequencyDistribution {
                case .missing:
                    Text(GPUFrequencyDistributionCopy.missing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                case .bars(let bars):
                    ForEach(bars) { bar in
                        distributionRow(bar)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(distributionAccessibilityLabel)
    }

    private func distributionRow(_ bar: GPUFrequencyDistributionBar) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(bar.label)
                    .font(.callout)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(bar.percentText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            distributionBar(bar.fraction)
        }
    }

    /// Hidden from VoiceOver so the percent text keeps the real value.
    private func distributionBar(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(PulsePalette.accent)
                    .frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var distributionAccessibilityLabel: String {
        switch vm.gpuFrequencyDistribution {
        case .missing:
            return "\(GPUFrequencyDistributionCopy.title)，\(GPUFrequencyDistributionCopy.missing)"
        case .bars(let bars):
            let parts = bars.map { "\($0.label) \($0.percentText)" }.joined(separator: "，")
            return "\(GPUFrequencyDistributionCopy.title)，\(parts)"
        }
    }
}
