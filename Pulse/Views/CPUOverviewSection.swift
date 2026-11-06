import SwiftUI

struct CPUOverviewSection: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        Group {
            switch vm.loadState {
            case .sampling:
                samplingBody
            case .failed:
                failureBody
            case .ready:
                readyBody
            }
        }
    }

    private var overviewLine: String {
        CPUPageCopy.overviewLine(systemCpuPercent: vm.systemCpuPercent)
    }

    private var samplingBody: some View {
        PulseCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    cpuLabel
                    SkeletonBlock(width: 120, height: 28)
                    Text(CPUPageCopy.sampling)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(width: 200, alignment: .leading)
                SkeletonChart()
            }
        }
        .frame(height: 150)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(overviewLine)，\(CPUPageCopy.sampling)")
    }

    private var failureBody: some View {
        AppEmptyState(
            systemImage: "cpu",
            title: CPUPageCopy.failureTitle,
            message: CPUPageCopy.failureMessage,
            retrying: vm.isRetrying,
            onRetry: vm.retrySampling
        )
        .frame(minHeight: 150)
        .background(PulsePalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(PulsePalette.hairline, lineWidth: 1)
        }
    }

    private var readyBody: some View {
        PulseCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    cpuLabel
                    Text(CPUPercentText.string(vm.systemCpuPercent))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(overviewLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: 200, alignment: .leading)

                chart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readyAccessibilityLabel)
    }

    private var readyAccessibilityLabel: String {
        if let note = HistoryCurvePresentation.annotation(current: vm.systemCpuPercent, sampleCount: vm.cpuHistory.samples.count) {
            return "\(overviewLine)，\(note)"
        }
        return overviewLine
    }

    private var cpuLabel: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PulsePalette.chartCPU.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsePalette.chartCPU)
                }
            Text("CPU")
                .font(.subheadline.weight(.medium))
        }
    }

    @ViewBuilder
    private var chart: some View {
        if vm.cpuHistory.samples.count < 2 {
            ChartPlaceholder(text: "曲线采集中")
        } else {
            HistoryAnnotatedChart(
                annotation: HistoryCurvePresentation.annotation(current: vm.systemCpuPercent, sampleCount: vm.cpuHistory.samples.count)
            ) {
                SparklineChart(
                    samples: vm.cpuHistory.samples,
                    tint: PulsePalette.chartCPU,
                    domain: domain,
                    formatY: { CPUPercentText.string($0) }
                )
            }
        }
    }

    private var domain: ClosedRange<Double> {
        let peak = vm.cpuHistory.samples.map(\.value).max() ?? 0
        return 0...max(peak * 1.2, 5)
    }
}
