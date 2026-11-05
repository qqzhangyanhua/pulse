import SwiftUI

struct ProcessDetailSidebar: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        Group {
            if let detail = vm.detail ?? selectedFallback {
                detailBody(detail)
            } else {
                emptyBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulsePalette.sidebar)
    }

    private var selectedFallback: ProcessDetail? {
        guard let row = vm.selectedRow else { return nil }
        return ProcessDetail(row: row, memorySeries: [], cpuSeries: [])
    }

    private var emptyPrompt: String {
        switch vm.selectedPage {
        case .cpu:
            return CPUPageCopy.sidebarEmpty
        case .network:
            return NetworkPageCopy.sidebarEmpty
        case .disk:
            return DiskPageCopy.sidebarEmpty
        default:
            return "选择一个进程查看详情"
        }
    }

    private var emptyBody: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(PulsePalette.accent.opacity(0.20))
                    .frame(width: 120, height: 120)
                    .blur(radius: 28)
                Image(systemName: "brain")
                    .font(.system(size: 68, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.74, green: 0.64, blue: 1),
                                Color(red: 0.45, green: 0.34, blue: 0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color(red: 0.58, green: 0.48, blue: 0.96))
                    .offset(x: 30, y: 22)
            }
            .frame(height: 120)
            .accessibilityHidden(true)

            Text(emptyPrompt)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func detailBody(_ detail: ProcessDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(detail)
                metrics(detail)
                if let slot = vm.memoryGrowthSlot {
                    memoryTrend(slot)
                }
                memoryChart(detail)
                    .frame(height: 168)
                cpuChart(detail)
                    .frame(height: 124)
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    private func header(_ detail: ProcessDetail) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProcessIconView(
                pid: detail.row.pid,
                bundleIdentifier: detail.row.bundleIdentifier,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.row.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(kindLine(detail.row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                vm.selectedPid = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭详情")
            .help("关闭详情")
        }
    }

    private func kindLine(_ row: ProcessRow) -> String {
        let kind = row.bundleIdentifier == nil ? "进程" : "App"
        return "\(kind) · PID \(row.pid)"
    }

    private func metrics(_ detail: ProcessDetail) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SidebarMetric(
                systemImage: "memorychip",
                title: "内存",
                tint: PulsePalette.accent,
                value: ByteFormat.memory(detail.row.memoryBytes),
                caption: memoryCaption(detail.row)
            )
            SidebarMetric(
                systemImage: "cpu",
                title: "CPU",
                tint: PulsePalette.chartCPU,
                value: ByteFormat.cpu(detail.row.cpuPercent),
                caption: ByteFormat.coreLoad(
                    cpuPercent: detail.row.cpuPercent,
                    processorCount: MachineInfo.processorCount
                )
            )
        }
    }

    private func memoryTrend(_ slot: MemoryGrowthSlot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(slot.title)
                .font(.caption.weight(.semibold))
            Text(slot.caption)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func memoryCaption(_ row: ProcessRow) -> String {
        guard let total = vm.snapshot?.totalBytes, total > 0 else { return "占物理内存" }
        return "占 \(ByteFormat.gibWhole(total)) 的 \(ByteFormat.share(part: row.memoryBytes, total: total))"
    }

    private func memoryChart(_ detail: ProcessDetail) -> some View {
        seriesBlock(
            title: "内存",
            samples: detail.memorySeries,
            placeholder: "正在采集内存曲线",
            summary: memorySummary(detail.memorySeries),
            tint: PulsePalette.accent,
            domain: byteDomain(detail.memorySeries),
            formatY: { ByteFormat.memory(UInt64(max(0, $0))) }
        )
    }

    private func cpuChart(_ detail: ProcessDetail) -> some View {
        seriesBlock(
            title: "CPU",
            samples: detail.cpuSeries,
            placeholder: "正在采集 CPU 曲线",
            summary: cpuSummary(detail.cpuSeries),
            tint: PulsePalette.chartCPU,
            domain: percentDomain(detail.cpuSeries),
            formatY: { ByteFormat.cpu($0) }
        )
    }

    private func memorySummary(_ samples: [ChartSample]) -> String {
        guard let latest = samples.seriesLatest, let peak = samples.seriesPeak else { return "" }
        return "最近 \(ByteFormat.memory(UInt64(max(0, latest)))) · 峰值 \(ByteFormat.memory(UInt64(max(0, peak))))"
    }

    private func cpuSummary(_ samples: [ChartSample]) -> String {
        guard let average = samples.seriesAverage, let peak = samples.seriesPeak else { return "" }
        return "平均 \(ByteFormat.cpu(average)) · 峰值 \(ByteFormat.cpu(peak))"
    }

    private func byteDomain(_ samples: [ChartSample]) -> ClosedRange<Double> {
        let peak = samples.map(\.value).max() ?? 0
        return 0...max(peak * 1.15, 1)
    }

    private func percentDomain(_ samples: [ChartSample]) -> ClosedRange<Double> {
        let peak = samples.map(\.value).max() ?? 0
        return 0...max(peak * 1.2, 5)
    }

    private func seriesBlock(
        title: String,
        samples: [ChartSample],
        placeholder: String,
        summary: String,
        tint: Color,
        domain: ClosedRange<Double>,
        formatY: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if samples.count < 2 {
                ChartPlaceholder(text: placeholder)
            } else {
                SparklineChart(samples: samples, tint: tint, domain: domain, formatY: formatY)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let quitMessage = vm.quitMessage {
                Text(quitMessage)
                    .font(.caption)
                    .foregroundStyle(PulsePalette.pressureElevated)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if vm.quitPhase == .quitting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在退出…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button {
                    Task { await vm.forceQuitSelected() }
                } label: {
                    Text("强制退出…")
                        .foregroundStyle(PulsePalette.destructive)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(PulsePalette.destructive)
                .controlSize(.large)
                .disabled(vm.quitPhase == .quitting)

                Button {
                    Task { await vm.quitSelected() }
                } label: {
                    Label("退出", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulsePalette.action)
                .controlSize(.large)
                .disabled(vm.quitPhase == .quitting)
            }
        }
        .padding(16)
        .background(PulsePalette.sidebar)
    }
}

private struct SidebarMetric: View {
    let systemImage: String
    let title: String
    let tint: Color
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.caption)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(PulsePalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PulsePalette.hairline, lineWidth: 1)
        }
    }
}
