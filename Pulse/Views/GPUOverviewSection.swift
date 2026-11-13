import SwiftUI

/// Full GPU page. Two readings, an optional core-count line, one utilization curve, the top GPU-share card, and the shared throttle card.
struct GPUOverviewSection: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThermalAdviceCard()
            switch vm.gpuPage.chrome {
            case .skeleton:
                skeletonBody
            case .samplingFailure:
                failureBody
            case .readings:
                readingsBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var skeletonBody: some View {
        PulseCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 16) {
                    metricLabel(GPUPageCopy.utilization, symbol: "display")
                    SkeletonBlock(width: 120, height: 28)
                    metricLabel(GPUPageCopy.memory, symbol: "memorychip")
                    SkeletonBlock(width: 140, height: 28)
                    Text(GPUPageCopy.sampling)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(width: 220, alignment: .leading)
                SkeletonChart()
            }
        }
        .frame(minHeight: 220)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(GPUPageCopy.utilization)，\(GPUPageCopy.sampling)")
    }

    private var failureBody: some View {
        AppEmptyState(
            systemImage: "display",
            title: GPUPageCopy.failureTitle,
            message: GPUPageCopy.failureMessage,
            retrying: vm.isRetrying,
            onRetry: vm.retrySampling
        )
        .frame(minHeight: 220)
        .background(PulsePalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(PulsePalette.hairline, lineWidth: 1)
        }
    }

    private var readingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    readingCard(title: GPUPageCopy.utilization, value: vm.gpuPage.utilizationText, symbol: "display")
                    readingCard(title: GPUPageCopy.memory, value: vm.gpuPage.memoryText, symbol: "memorychip")
                }
                .frame(height: 132)
                VStack(alignment: .leading, spacing: 4) {
                    Text(EnergyModelCopy.gpuPowerLine(watts: vm.cpuEnergy?.gpuWatts))
                    Text(EnergyModelCopy.gpuFrequencyLine(hertz: vm.cpuEnergy?.gpuHertz))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let cores = vm.gpuPage.coreCountText {
                    Text(cores)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HistoryRangeControl(range: vm.historyCurveRange, select: vm.selectHistoryCurveRange)
                PulseCard {
                    chart
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 180)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            GPUShareCard()
        }
    }

    private var accessibilityLabel: String {
        var line = "\(GPUPageCopy.utilization) \(vm.gpuPage.utilizationText)，\(GPUPageCopy.memory) \(vm.gpuPage.memoryText)"
        line += "，\(EnergyModelCopy.gpuPowerLine(watts: vm.cpuEnergy?.gpuWatts))"
        line += "，\(EnergyModelCopy.gpuFrequencyLine(hertz: vm.cpuEnergy?.gpuHertz))"
        if let cores = vm.gpuPage.coreCountText {
            line += "，\(cores)"
        }
        if let note = HistoryCurvePresentation.annotation(
            current: vm.gpuPage.utilizationPercent,
            sampleCount: vm.gpuPage.history.samples.count
        ) {
            return "\(line)，\(note)"
        }
        return line
    }

    private func readingCard(title: String, value: String, symbol: String) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                metricLabel(title, symbol: symbol)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func metricLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PulsePalette.accent.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsePalette.accent)
                }
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let plot = vm.historyCurvePlot(\.gpuPercent) {
            HistoryRangeChart(
                plot: plot,
                tint: PulsePalette.accent,
                domain: domain,
                formatY: { CPUPercentText.string($0) }
            )
        } else if vm.gpuPage.showsCurve {
            HistoryAnnotatedChart(
                annotation: HistoryCurvePresentation.annotation(
                    current: vm.gpuPage.utilizationPercent,
                    sampleCount: vm.gpuPage.history.samples.count
                )
            ) {
                SparklineChart(
                    samples: vm.gpuPage.history.samples,
                    tint: PulsePalette.accent,
                    domain: domain,
                    formatY: { CPUPercentText.string($0) }
                )
            }
        } else {
            ChartPlaceholder(text: GPUPageCopy.chartCollecting)
        }
    }

    private var domain: ClosedRange<Double> {
        let live = vm.gpuPage.history.samples.map(\.value).max() ?? 0
        let stored = vm.historyCurvePlot(\.gpuPercent)?.points.compactMap(\.value).max() ?? 0
        return 0...max(max(live, stored) * 1.2, 5)
    }
}
