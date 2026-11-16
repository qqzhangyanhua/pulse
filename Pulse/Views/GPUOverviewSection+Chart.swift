import SwiftUI

extension GPUOverviewSection {
    var chartCard: some View {
        let summary = curveSummary
        return PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(GPUPageCopy.utilization)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    summaryPill(GPUCurveSummary.meanTitle, summary.meanText)
                    summaryPill(GPUCurveSummary.peakTitle, summary.peakText)
                }
                chart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .frame(minHeight: 180)
    }

    private var curveSummary: GPUCurveSummary {
        vm.gpuPage.curveSummary(
            range: vm.historyCurveRange,
            historyPoints: vm.historyCurvePlot(\.gpuPercent)?.points.map(\.value) ?? []
        )
    }

    private func summaryPill(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.85))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
