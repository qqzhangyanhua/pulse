import SwiftUI

struct DiskOverviewSection: View {
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
        DiskPageCopy.overviewLine(rates: vm.hostDiskRates)
    }

    private var samplingBody: some View {
        VStack(spacing: 12) {
            ThermalAdviceCard()
            HStack(spacing: 12) {
                samplingCard(
                    title: DiskPageCopy.readTitle,
                    symbol: "arrow.down",
                    thermalNotice: vm.thermalAdvice == nil ? vm.thermalNotice : nil
                )
                samplingCard(title: DiskPageCopy.writeTitle, symbol: "arrow.up")
            }
            .frame(height: 150)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(overviewLine)，\(DiskPageCopy.sampling)")
        }
    }

    private var failureBody: some View {
        AppEmptyState(
            systemImage: "internaldrive",
            title: DiskPageCopy.failureTitle,
            message: DiskPageCopy.failureMessage,
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
            ThermalAdviceCard()
            HistoryRangeControl(range: vm.historyCurveRange, select: vm.selectHistoryCurveRange)
            HStack(spacing: 12) {
                DiskRateCard(
                    title: DiskPageCopy.readTitle,
                    symbol: "arrow.down",
                    rate: vm.hostDiskRates.readBytesPerSecond,
                    samples: vm.diskHistory.read.samples,
                    thermalNotice: vm.thermalAdvice == nil ? vm.thermalNotice : nil,
                    history: vm.historyCurvePlot(\.diskReadBytesPerSecond)
                )
                DiskRateCard(
                    title: DiskPageCopy.writeTitle,
                    symbol: "arrow.up",
                    rate: vm.hostDiskRates.writeBytesPerSecond,
                    samples: vm.diskHistory.write.samples,
                    history: vm.historyCurvePlot(\.diskWriteBytesPerSecond)
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
                title: DiskPageCopy.readTitle,
                note: HistoryCurvePresentation.annotation(
                    current: vm.hostDiskRates.readBytesPerSecond,
                    sampleCount: vm.diskHistory.read.samples.count
                )
            ),
            directedHistoryNote(
                title: DiskPageCopy.writeTitle,
                note: HistoryCurvePresentation.annotation(
                    current: vm.hostDiskRates.writeBytesPerSecond,
                    sampleCount: vm.diskHistory.write.samples.count
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
                    diskLabel(title: title, symbol: symbol)
                    SkeletonBlock(width: 120, height: 28)
                    Text(DiskPageCopy.sampling)
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

    private func diskLabel(title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PulsePalette.chartDisk.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsePalette.chartDisk)
                }
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }
}

private struct DiskRateCard: View {
    let title: String
    let symbol: String
    let rate: Double?
    let samples: [ChartSample]
    var thermalNotice: String? = nil
    var history: HistoryCurvePlot? = nil

    var body: some View {
        PulseCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    label
                    Text(DiskRateText.string(rate))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(title) · \(DiskRateText.string(rate))")
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
                .fill(PulsePalette.chartDisk.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsePalette.chartDisk)
                }
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }

    private var chart: some View {
        HistoryRateChart(
            history: history,
            samples: samples,
            rate: rate,
            tint: PulsePalette.chartDisk,
            domain: domain,
            placeholder: DiskPageCopy.chartCollecting,
            formatY: { DiskRateText.string($0) }
        )
    }

    private var domain: ClosedRange<Double> {
        let live = samples.map(\.value).max() ?? 0
        let stored = history?.points.compactMap(\.value).max() ?? 0
        return 0...max(max(live, stored) * 1.2, 1_024)
    }
}
