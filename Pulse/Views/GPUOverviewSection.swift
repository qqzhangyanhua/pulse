import SwiftUI

/// Full GPU page. Spec labels, four reading cards, two visit sparklines, one utilization curve, the GPU-share card, recovery count, the frequency-distribution card, the hour GPU-time card, and the display card.
struct GPUOverviewSection: View {
    /// Internal so the readings, chart, and share extensions share one environment object.
    @EnvironmentObject var vm: MemoryDashboardVM

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ThermalAdviceCard()
                switch vm.gpu.page.chrome {
                case .skeleton:
                    skeletonBody
                case .samplingFailure:
                    failureBody
                case .readings:
                    readingsBody
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
                specLabels
                readingCards
                HistoryRangeControl(range: vm.historyCurveRange, select: vm.selectHistoryCurveRange)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            chartAndShare
            recoveryCard
            frequencyDistributionCard
            gpuTimeCard
            displaysCard
        }
    }

    private var accessibilityLabel: String {
        var line = "\(MachinePageCopy.chipValue(vm.machineFacts?.chipName))"
        line += "，\(GPUPageCopy.utilization) \(vm.gpu.page.utilizationText)，\(GPUPageCopy.renderer) \(vm.gpu.page.rendererText)，\(GPUPageCopy.tiler) \(vm.gpu.page.tilerText)，\(GPUPageCopy.memory) \(vm.gpu.page.memoryText)"
        line += "，\(vm.gpu.powerLine)"
        line += "，\(vm.gpu.frequencyLine)"
        if let cores = vm.gpu.page.coreCountText {
            line += "，\(cores)"
        }
        if let note = HistoryCurvePresentation.annotation(
            current: vm.gpu.page.utilizationPercent,
            sampleCount: vm.gpu.page.history.samples.count
        ) {
            return "\(line)，\(note)"
        }
        return line
    }
}
