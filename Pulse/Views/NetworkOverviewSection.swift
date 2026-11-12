import SwiftUI

struct NetworkOverviewSection: View {
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
        NetworkPageCopy.overviewLine(rates: vm.hostNetworkRates)
    }

    @ViewBuilder
    private var thermalAdviceCard: some View {
        if let advice = vm.thermalAdvice {
            ThermalAdviceCard(advice: advice, onTerminate: { pid in
                Task { await vm.terminateThermalAdvice(pid: pid) }
            })
        }
    }

    private var samplingBody: some View {
        VStack(spacing: 12) {
            thermalAdviceCard
            HStack(spacing: 12) {
                samplingCard(
                    title: NetworkPageCopy.inboundTitle,
                    symbol: "arrow.down",
                    thermalNotice: vm.thermalAdvice == nil ? vm.thermalNotice : nil
                )
                samplingCard(title: NetworkPageCopy.outboundTitle, symbol: "arrow.up")
            }
            .frame(height: 150)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(overviewLine)，\(NetworkPageCopy.sampling)")
        }
    }

    private var failureBody: some View {
        AppEmptyState(
            systemImage: "network",
            title: NetworkPageCopy.failureTitle,
            message: NetworkPageCopy.failureMessage,
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
        VStack(spacing: 12) {
            thermalAdviceCard
            HStack(spacing: 12) {
                NetworkRateCard(
                    title: NetworkPageCopy.inboundTitle,
                    symbol: "arrow.down",
                    rate: vm.hostNetworkRates.inboundBytesPerSecond,
                    samples: vm.networkHistory.inbound.samples,
                    thermalNotice: vm.thermalAdvice == nil ? vm.thermalNotice : nil
                )
                NetworkRateCard(
                    title: NetworkPageCopy.outboundTitle,
                    symbol: "arrow.up",
                    rate: vm.hostNetworkRates.outboundBytesPerSecond,
                    samples: vm.networkHistory.outbound.samples
                )
            }
            .frame(height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(readyAccessibilityLabel)
        }
    }

    private var readyAccessibilityLabel: String {
        let notes = [
            directedHistoryNote(
                title: NetworkPageCopy.inboundTitle,
                note: HistoryCurvePresentation.annotation(
                    current: vm.hostNetworkRates.inboundBytesPerSecond,
                    sampleCount: vm.networkHistory.inbound.samples.count
                )
            ),
            directedHistoryNote(
                title: NetworkPageCopy.outboundTitle,
                note: HistoryCurvePresentation.annotation(
                    current: vm.hostNetworkRates.outboundBytesPerSecond,
                    sampleCount: vm.networkHistory.outbound.samples.count
                )
            ),
        ].compactMap { $0 }
        guard !notes.isEmpty else { return overviewLine }
        return ([overviewLine] + notes).joined(separator: "，")
    }

    private func directedHistoryNote(title: String, note: String?) -> String? {
        guard let note else { return nil }
        return "\(title) · \(note)"
    }

    private func samplingCard(title: String, symbol: String, thermalNotice: String? = nil) -> some View {
        PulseCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    networkLabel(title: title, symbol: symbol)
                    SkeletonBlock(width: 120, height: 28)
                    Text(NetworkPageCopy.sampling)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let thermalNotice {
                        ThermalNoticeLine(text: thermalNotice)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 168, alignment: .leading)
                SkeletonChart()
            }
        }
    }

    private func networkLabel(title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PulsePalette.chartNetwork.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsePalette.chartNetwork)
                }
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }
}

private struct NetworkRateCard: View {
    let title: String
    let symbol: String
    let rate: Double?
    let samples: [ChartSample]
    var thermalNotice: String? = nil

    var body: some View {
        PulseCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    label
                    Text(NetworkRateText.string(rate))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(title) · \(NetworkRateText.string(rate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let thermalNotice {
                        ThermalNoticeLine(text: thermalNotice)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 168, alignment: .leading)

                chart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PulsePalette.chartNetwork.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsePalette.chartNetwork)
                }
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }

    @ViewBuilder
    private var chart: some View {
        if samples.count < 2 {
            ChartPlaceholder(text: NetworkPageCopy.chartCollecting)
        } else {
            HistoryAnnotatedChart(
                annotation: HistoryCurvePresentation.annotation(current: rate, sampleCount: samples.count)
            ) {
                SparklineChart(
                    samples: samples,
                    tint: PulsePalette.chartNetwork,
                    domain: domain,
                    formatY: { NetworkRateText.string($0) }
                )
            }
        }
    }

    private var domain: ClosedRange<Double> {
        let peak = samples.map(\.value).max() ?? 0
        return 0...max(peak * 1.2, 1_024)
    }
}
