import SwiftUI

/// Host facts, the current load, and the CPU and memory series already on the dashboard.
/// Disk, power, and uptime stay numbers. There is no process list.
struct MachineOverviewSection: View {
    /// Internal so `MachineOverviewSection+Throughput` can read the same environment object.
    @EnvironmentObject var vm: MemoryDashboardVM

    var body: some View {
        let model = MachineOverview.project(
            facts: vm.machineFacts, snapshot: vm.snapshot, loadState: vm.loadState,
            cpuPercent: vm.systemCpuPercent, cpuSeries: vm.cpuHistory.samples,
            memorySeries: vm.usageHistory.samples, thermalNotice: vm.thermalNotice
        )
        VStack(alignment: .leading, spacing: 12) {
            ThermalAdviceCard()
            HStack(spacing: 12) {
                identity(model).frame(minWidth: 310, idealWidth: 344, maxWidth: 376)
                cpuMetricCard(model.cpu)
                memoryMetricCard(model.memory)
            }
            .frame(height: 192)

            HStack(spacing: 12) {
                factCard(model.uptime, symbol: "clock", tint: PulsePalette.chartCPU, badge: vm.rows.isEmpty ? nil : "\(vm.rows.count) 进程")
                factCard(model.power, symbol: "bolt.fill", tint: PulsePalette.pressureElevated, barFraction: model.power.batteryPercent.map { Double(min(max($0, 0), 100)) / 100.0 }, barTint: (model.power.batteryPercent ?? 100) <= 20 ? PulsePalette.pressureElevated : PulsePalette.pressureNormal)
                factCard(model.disk, symbol: "internaldrive", tint: PulsePalette.chartDisk, badge: vm.machineFacts?.volume.availableBytes.map { "可用 \(ByteFormat.memory($0))" }, barFraction: diskUsedFraction, barTint: (diskUsedFraction ?? 0) >= 0.9 ? PulsePalette.pressureElevated : PulsePalette.chartDisk)
                factCard(model.swap, symbol: "arrow.left.arrow.right", tint: PulsePalette.accent, badge: vm.snapshot.map { "被压缩 \(ByteFormat.memory($0.breakdown.compressedBytes))" })
            }
            .frame(height: 142)

            if let battery = model.battery {
                batteryBlock(battery)
            }

            HStack(spacing: 12) {
                ioThroughputCard
                topWorkloadCard
                diagnostics(model)
            }
            .frame(minHeight: 200, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func identity(_ model: MachineOverview.Model) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    iconLabel(model.identity.title, symbol: "desktopcomputer", tint: PulsePalette.accent)
                    Spacer(minLength: 4)
                    HStack(spacing: 5) {
                        Circle().fill(ringTint(model.ring.tone)).frame(width: 6, height: 6)
                        Text(model.liveUpdate).font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.white.opacity(0.04), in: Capsule())
                }
                HStack(alignment: .center, spacing: 14) {
                    identityLines(model.identity).frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                    pressureRing(model.ring)
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 6) {
                    specPill(symbol: "macwindow", text: model.identity.system ?? "—")
                    specPill(symbol: "memorychip", text: model.identity.capacity ?? "—")
                    specPill(symbol: "square.stack.3d.up", text: vm.rows.isEmpty ? "—" : "\(vm.rows.count) 进程 · \(totalThreads) 线程")
                }
            }
        }
    }

    @ViewBuilder
    private func identityLines(_ identity: MachineOverview.Identity) -> some View {
        if identity.loading {
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 156, height: 22)
                Text("正在读取本机…").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(identity.model ?? "—").font(.system(size: 22, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 5) {
                    Image(systemName: "cpu.fill").font(.caption2).foregroundStyle(PulsePalette.accent)
                    Text(identity.chip ?? "—").font(.subheadline.weight(.medium)).foregroundStyle(Color.white.opacity(0.86)).lineLimit(1)
                }
            }
        }
    }

    private func specPill(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(text).font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(PulsePalette.hairline, lineWidth: 1))
    }

    private func pressureRing(_ ring: MachineOverview.Ring) -> some View {
        let tint = ringTint(ring.tone)
        let active = ring.tone == .normal || ring.tone == .elevated
        return Button { open(ring.page) } label: {
            ZStack {
                Circle().fill(active ? tint.opacity(0.10) : Color.white.opacity(0.03))
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 5)
                if active { Circle().stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)) }
                VStack(spacing: 2) {
                    Text("压力").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    if let label = ring.label {
                        Text(label).font(.callout.weight(.semibold))
                            .foregroundStyle(ring.tone == .missing ? Color.secondary : tint).lineLimit(1)
                    } else {
                        SkeletonBlock(width: 28, height: 12)
                    }
                }
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain).accessibilityElement(children: .ignore)
        .accessibilityLabel(ringAccessibility(ring)).accessibilityAddTraits(.isButton)
    }

    private func cpuMetricCard(_ card: MachineOverview.Card) -> some View {
        metricCard(card, symbol: "cpu", tint: PulsePalette.chartCPU, domain: percentDomain, format: { CPUPercentText.string($0) }) {
            HStack(spacing: 8) {
                metricSubPill(title: "单核最高", value: vm.busiestCorePercent.map { CPUPercentText.string($0) } ?? "—", tint: PulsePalette.chartCPU)
                metricSubPill(title: "均值", value: card.series?.seriesAverage.map { CPUPercentText.string($0) } ?? "—", tint: .secondary)
                metricSubPill(title: "峰值", value: card.series?.seriesPeak.map { CPUPercentText.string($0) } ?? "—", tint: .secondary)
            }
        }
    }

    private func memoryMetricCard(_ card: MachineOverview.Card) -> some View {
        metricCard(card, symbol: "memorychip", tint: PulsePalette.accent, domain: byteDomain, format: { ByteFormat.memory(UInt64(max(0, $0))) }) {
            if let snapshot = vm.snapshot {
                VStack(alignment: .leading, spacing: 5) {
                    CategoryBar(breakdown: snapshot.breakdown).frame(height: 6)
                    HStack(spacing: 10) {
                        miniLegendDot("App", bytes: snapshot.breakdown.appBytes, color: PulsePalette.app)
                        miniLegendDot("联动", bytes: snapshot.breakdown.wiredBytes, color: PulsePalette.wired)
                        miniLegendDot("压缩", bytes: snapshot.breakdown.compressedBytes, color: PulsePalette.compressed)
                        miniLegendDot("缓存", bytes: snapshot.breakdown.cachedBytes, color: PulsePalette.cached)
                    }
                }
            } else {
                SkeletonBlock(width: nil, height: 18)
            }
        }
    }

    private func metricCard<Footer: View>(
        _ card: MachineOverview.Card, symbol: String, tint: Color,
        domain: @escaping ([ChartSample]) -> ClosedRange<Double>,
        format: @escaping (Double) -> String, @ViewBuilder footer: () -> Footer
    ) -> some View {
        let footerView = footer()
        return linked(card) {
            PulseCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            cardHeader(card.title, symbol: symbol, tint: tint, linked: card.page != nil)
                            Spacer(minLength: 0)
                            reading(card, size: 30)
                            caption(card)
                        }
                        .frame(width: 146, alignment: .leading)
                        metricChart(card, tint: tint, domain: domain, format: format).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    footerView
                }
            }
        }
    }

    private func miniLegendDot(_ title: String, bytes: UInt64, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(title) \(ByteFormat.memory(bytes))").font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricSubPill(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint == .secondary ? Color.primary.opacity(0.85) : tint).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 4).frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func metricChart(
        _ card: MachineOverview.Card, tint: Color,
        domain: @escaping ([ChartSample]) -> ClosedRange<Double>, format: @escaping (Double) -> String
    ) -> some View {
        if let series = card.series {
            HistoryAnnotatedChart(annotation: card.seriesNote) {
                SparklineChart(samples: series, tint: tint, domain: domain(series), formatY: format)
            }
        } else if card.value == nil {
            SkeletonChart()
        } else {
            ChartPlaceholder(text: "曲线采集中")
        }
    }

    private func factCard(
        _ card: MachineOverview.Card, symbol: String, tint: Color,
        badge: String? = nil, barFraction: Double? = nil, barTint: Color = PulsePalette.accent
    ) -> some View {
        linked(card) {
            PulseCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        iconLabel(card.title, symbol: symbol, tint: tint)
                        Spacer(minLength: 0)
                        if let badge {
                            Text(badge).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                                .monospacedDigit().lineLimit(1).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.white.opacity(0.05), in: Capsule())
                        }
                        if card.page != nil { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    }
                    Spacer(minLength: 0)
                    reading(card, size: 25)
                    if let barFraction { progressBar(fraction: barFraction, tint: barTint) }
                    caption(card)
                }
            }
        }
    }

    private var topWorkloadCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    iconLabel("高占用应用", symbol: "flame", tint: PulsePalette.app)
                    Spacer(minLength: 4)
                    Button { open(.memory) } label: {
                        HStack(spacing: 3) {
                            Text("查看全部").font(.caption2)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if topProcesses.isEmpty {
                    Text("正在汇总活跃进程…").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 7) {
                        ForEach(topProcesses, id: \.pid) { row in topProcessRow(row) }
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func topProcessRow(_ row: ProcessRow) -> some View {
        let fraction = min(max(Double(row.memoryBytes) / Double(max(vm.snapshot?.totalBytes ?? 1, 1)), 0.02), 1.0)
        return HStack(spacing: 8) {
            ProcessIconView(pid: row.pid, bundleIdentifier: row.bundleIdentifier, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).font(.caption.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(CPUPercentText.string(row.cpuPercent)).font(.caption2).foregroundStyle(PulsePalette.chartCPU).monospacedDigit()
                    Text(ByteFormat.memory(row.memoryBytes)).font(.caption.weight(.semibold)).monospacedDigit()
                }
                progressBar(fraction: fraction, tint: PulsePalette.app, height: 4)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func reading(_ card: MachineOverview.Card, size: CGFloat) -> some View {
        if let value = card.value {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: size, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                if let delta = card.delta {
                    Text(delta).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .monospacedDigit().lineLimit(1).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.white.opacity(0.05), in: Capsule())
                }
            }
        } else {
            SkeletonBlock(width: 96, height: size * 0.85)
        }
    }

    @ViewBuilder
    private func caption(_ card: MachineOverview.Card) -> some View {
        if let caption = card.caption, !caption.isEmpty {
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        } else if card.value == nil {
            SkeletonBlock(width: 72, height: 10)
        }
    }

    private func batteryBlock(_ battery: MachineOverview.Battery) -> some View {
        PulseCard {
            HStack(spacing: 12) {
                batteryReading(title: "循环次数", value: battery.cycles)
                batteryReading(title: "健康度", value: battery.health)
                batteryReading(title: "功率", value: battery.power)
            }
        }
        .frame(height: 72)
        .accessibilityElement(children: .combine)
    }

    private func batteryReading(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressBar(fraction: Double, tint: Color, height: CGFloat = 6) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(tint).frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height).accessibilityHidden(true)
    }

    private func diagnostics(_ model: MachineOverview.Model) -> some View {
        PulseCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    iconLabel("状态概览", symbol: "waveform.path.ecg", tint: PulsePalette.accent)
                    Spacer(minLength: 4)
                    if vm.thermalAdvice == nil, let notice = model.thermalNotice {
                        ThermalNoticeLine(text: notice).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(PulsePalette.pressureElevated.opacity(0.14), in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, item in diagnostic(item) }
                }
                .frame(height: 64)
                pressureTrendBlock
            }
        }
    }

    @ViewBuilder
    private var pressureTrendBlock: some View {
        let series = vm.snapshot?.pressureSeries ?? []
        let tone = vm.snapshot?.pressure == .elevated ? PulsePalette.pressureElevated : PulsePalette.pressureNormal
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("内存压力趋势").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let avg = series.seriesAverage {
                    Text("平均 \(ByteFormat.wholePercent(value: avg))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                if let peak = series.seriesPeak {
                    Text("峰值 \(ByteFormat.wholePercent(value: peak))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if series.count >= 2 {
                SparklineChart(samples: series, tint: tone, domain: 0...1, formatY: { ByteFormat.wholePercent(value: $0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ChartPlaceholder(text: "压力曲线采集中").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var totalThreads: Int { vm.rows.reduce(0) { $0 + max(0, $1.threadCount) } }
    private var topProcesses: [ProcessRow] { Array(vm.rows.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(4)) }
    private var diskUsedFraction: Double? {
        guard let available = vm.machineFacts?.volume.availableBytes,
              let total = vm.machineFacts?.volume.totalBytes, total > 0, available <= total else { return nil }
        return Double(total - available) / Double(total)
    }

    @ViewBuilder
    private func diagnostic(_ item: MachineOverview.Diagnostic) -> some View {
        if let page = item.page {
            Button { open(page) } label: { diagnosticLabel(item, linked: true) }
                .buttonStyle(.plain).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityElement(children: .ignore).accessibilityLabel(diagnosticAccessibility(item, page: page))
                .accessibilityAddTraits(.isButton)
        } else {
            diagnosticLabel(item, linked: false).accessibilityElement(children: .combine)
        }
    }

    private func diagnosticLabel(_ item: MachineOverview.Diagnostic, linked: Bool) -> some View {
        let tone = statusColor(item.status)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(item.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if linked { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
            }
            HStack(spacing: 6) {
                Circle().fill(tone).frame(width: 7, height: 7)
                Text(item.status).font(.headline).foregroundStyle(tone).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(PulsePalette.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func linked<Content: View>(_ card: MachineOverview.Card, @ViewBuilder content: () -> Content) -> some View {
        if let page = card.page {
            Button { open(page) } label: { content() }
                .buttonStyle(.plain).accessibilityElement(children: .ignore)
                .accessibilityLabel(cardAccessibility(card, page: page)).accessibilityAddTraits(.isButton)
        } else {
            content().accessibilityElement(children: .combine)
        }
    }

    private func open(_ page: MachineOverview.Page) {
        if page == .memory { vm.selectPage(.memory) } else { vm.selectPage(.cpu) }
    }

    private func cardAccessibility(_ card: MachineOverview.Card, page: MachineOverview.Page) -> String {
        var value = card.value ?? card.caption ?? MachineStatusCopy.samplingCaption
        if let caption = card.caption, card.value != nil, caption != value { value += "，\(caption)" }
        if let delta = card.delta { value += "，\(delta)" }
        if let note = card.seriesNote { value += "，\(note)" }
        return MachineStatusCopy.buttonLabel(title: card.title, value: value, destination: destination(page))
    }

    private func ringAccessibility(_ ring: MachineOverview.Ring) -> String {
        MachineStatusCopy.buttonLabel(title: "压力", value: ring.label ?? MachineStatusCopy.samplingCaption, destination: destination(ring.page))
    }

    private func diagnosticAccessibility(_ item: MachineOverview.Diagnostic, page: MachineOverview.Page) -> String {
        MachineStatusCopy.buttonLabel(title: item.title, value: item.status, destination: destination(page))
    }

    private func destination(_ page: MachineOverview.Page) -> String {
        page == .memory ? MachineStatusCopy.memoryDestination : MachineStatusCopy.cpuDestination
    }

    private func ringTint(_ tone: MachineOverview.Ring.Tone) -> Color {
        tone == .normal ? PulsePalette.pressureNormal : (tone == .elevated ? PulsePalette.pressureElevated : .secondary)
    }

    private func statusColor(_ status: String) -> Color {
        status == PressureLevel.normal.title ? PulsePalette.pressureNormal : (status == PressureLevel.elevated.title ? PulsePalette.pressureElevated : .secondary)
    }

    private func cardHeader(_ title: String, symbol: String, tint: Color, linked: Bool) -> some View {
        HStack(spacing: 8) {
            iconLabel(title, symbol: symbol, tint: tint)
            Spacer(minLength: 0)
            if linked { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
        }
    }

    func iconLabel(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.22)).frame(width: 22, height: 22)
                .overlay(Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint))
            Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
        }
    }

    private func percentDomain(_ series: [ChartSample]) -> ClosedRange<Double> { 0...max((series.map(\.value).max() ?? 0) * 1.2, 5) }
    func byteDomain(_ series: [ChartSample]) -> ClosedRange<Double> { 0...max((series.map(\.value).max() ?? 0) * 1.2, 1) }
}
