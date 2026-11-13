import SwiftUI

struct OverviewSection: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        Group {
            switch vm.loadState {
            case .sampling:
                samplingBody
            case .failed:
                failureBody
            case .ready:
                if let snapshot = vm.snapshot {
                    readyBody(snapshot)
                } else {
                    failureBody
                }
            }
        }
    }

    private var samplingBody: some View {
        VStack(spacing: 12) {
            ThermalAdviceCard()
            HStack(spacing: 12) {
                samplingHero
                samplingComposition
                    .frame(width: 310)
            }
            .frame(height: 148)

            HStack(spacing: 12) {
                ForEach(SamplingStat.allCases) { stat in
                    samplingStat(stat)
                }
            }
            .frame(height: 104)
        }
    }

    private var samplingHero: some View {
        PulseCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("内存", systemImage: "memorychip")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    SkeletonBlock(width: 120, height: 28)
                    SkeletonBlock(width: 96, height: 10)
                    if vm.thermalAdvice == nil, let notice = vm.thermalNotice {
                        ThermalNoticeLine(text: notice)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 168, alignment: .leading)
                SkeletonChart()
            }
        }
    }

    private var samplingComposition: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("按类型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SkeletonBlock(height: 8)
                    .frame(maxWidth: .infinity)
                SkeletonBlock(height: 8)
                SkeletonBlock(width: 140, height: 8)
                SkeletonBlock(width: 110, height: 8)
                Spacer(minLength: 0)
            }
        }
    }

    private func samplingStat(_ stat: SamplingStat) -> some View {
        PulseCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label(stat.rawValue, systemImage: stat.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                SkeletonBlock(width: 72, height: 18)
                Spacer(minLength: 0)
            }
        }
    }

    private var failureBody: some View {
        AppEmptyState(
            systemImage: "waveform.path.ecg",
            title: "暂时读不到内存数据",
            message: SamplingRetryChrome.overviewFailureMessage,
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

    private func readyBody(_ snapshot: MemorySnapshot) -> some View {
        let available = snapshot.totalBytes > snapshot.usedBytes
            ? snapshot.totalBytes - snapshot.usedBytes
            : 0
        let swap = SwapUsage.display(usedBytes: snapshot.swapUsedBytes)
        let consumer = TopConsumer.leading(in: vm.rows)

        return VStack(spacing: 12) {
            ThermalAdviceCard()
            HStack(spacing: 12) {
                MemoryHeroCard(
                    snapshot: snapshot,
                    usedSeries: vm.usageHistory.samples,
                    thermalNotice: vm.thermalAdvice == nil ? vm.thermalNotice : nil
                )
                CompositionCard(breakdown: snapshot.breakdown, totalBytes: snapshot.totalBytes)
                    .frame(width: 310)
            }
            .frame(height: 148)

            HStack(spacing: 12) {
                PressureLevelCard(snapshot: snapshot)
                MetricStatCard(
                    systemImage: "memorychip",
                    title: "可用",
                    value: ByteFormat.memory(available),
                    caption: "空闲或可回收",
                    iconColor: PulsePalette.accent
                )
                MetricStatCard(
                    systemImage: "arrow.left.arrow.right",
                    title: "交换",
                    value: swap.value,
                    caption: swap.caption,
                    iconColor: .secondary
                )
                pageRateCard(
                    systemImage: "arrow.down.to.line",
                    title: MemoryPageCopy.pageIn,
                    value: vm.memoryPage.pageInText,
                    caption: MemoryPageCopy.pageInCaption
                )
                pageRateCard(
                    systemImage: "arrow.up.to.line",
                    title: MemoryPageCopy.pageOut,
                    value: vm.memoryPage.pageOutText,
                    caption: MemoryPageCopy.pageOutCaption
                )
                TopAppCard(consumer: consumer) { pid in
                    guard let consumer else { return }
                    vm.locateMemoryTopApp(name: consumer.name, pid: pid)
                }
            }
            .frame(height: 104)
        }
    }

    private func pageRateCard(
        systemImage: String,
        title: String,
        value: String,
        caption: String
    ) -> some View {
        MetricStatCard(
            systemImage: systemImage,
            title: title,
            value: value,
            caption: caption,
            iconColor: .secondary
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)，\(caption)")
    }
}

private enum SamplingStat: String, CaseIterable, Identifiable {
    case pressure = "压力"
    case available = "可用"
    case swap = "交换"
    case pageIn = "换入"
    case pageOut = "换出"
    case top = "占用最多的 App"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pressure: return "gauge.medium"
        case .available: return "memorychip"
        case .swap: return "arrow.left.arrow.right"
        case .pageIn: return "arrow.down.to.line"
        case .pageOut: return "arrow.up.to.line"
        case .top: return "crown.fill"
        }
    }
}
