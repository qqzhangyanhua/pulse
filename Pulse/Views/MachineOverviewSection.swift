import SwiftUI

/// Host facts, the current load, and the CPU and memory series already on the dashboard.
/// Disk, power, and uptime stay numbers. There is no process list.
struct MachineOverviewSection: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        let model = MachineOverview.project(
            facts: vm.machineFacts,
            snapshot: vm.snapshot,
            loadState: vm.loadState,
            cpuPercent: vm.systemCpuPercent,
            cpuSeries: vm.cpuHistory.samples,
            memorySeries: vm.usageHistory.samples,
            thermalNotice: vm.thermalNotice
        )
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                identity(model)
                metric(
                    model.cpu,
                    symbol: "cpu",
                    tint: PulsePalette.chartCPU,
                    domain: percentDomain,
                    format: { CPUPercentText.string($0) }
                )
                metric(
                    model.memory,
                    symbol: "memorychip",
                    tint: PulsePalette.accent,
                    domain: byteDomain,
                    format: { ByteFormat.memory(UInt64(max(0, $0))) }
                )
            }
            .frame(height: 172)

            HStack(spacing: 12) {
                fact(model.uptime, symbol: "clock", tint: PulsePalette.chartCPU)
                fact(model.power, symbol: "bolt", tint: PulsePalette.pressureElevated)
                fact(model.disk, symbol: "internaldrive", tint: PulsePalette.chartDisk)
                fact(model.swap, symbol: "arrow.left.arrow.right", tint: .secondary)
            }
            .frame(height: 148)

            if let battery = model.battery {
                batteryBlock(battery)
            }

            Text(model.liveUpdate)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            diagnostics(model)

            if let notice = model.thermalNotice {
                ThermalNoticeLine(text: notice)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func identity(_ model: MachineOverview.Model) -> some View {
        PulseCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    iconLabel(model.identity.title, symbol: "desktopcomputer", tint: PulsePalette.accent)
                    identityLines(model.identity)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                pressureRing(model.ring)
            }
        }
    }

    @ViewBuilder
    private func identityLines(_ identity: MachineOverview.Identity) -> some View {
        if identity.loading {
            SkeletonBlock(width: 160, height: 22)
            Text("正在读取本机…")
                .font(.caption)
                .foregroundStyle(.secondary)
            SkeletonBlock(width: 120, height: 10)
            SkeletonBlock(width: 96, height: 10)
        } else {
            Text(identity.model ?? "—")
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(identity.chip ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(identity.system ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(identity.capacity ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func pressureRing(_ ring: MachineOverview.Ring) -> some View {
        let tint = ringTint(ring.tone)
        return Button {
            open(ring.page)
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                if ring.tone == .normal || ring.tone == .elevated {
                    Circle()
                        .stroke(tint, lineWidth: 5)
                }
                if let label = ring.label {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ring.tone == .missing ? Color.secondary : tint)
                        .lineLimit(1)
                }
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ringAccessibility(ring))
        .accessibilityAddTraits(.isButton)
    }

    private func metric(
        _ card: MachineOverview.Card,
        symbol: String,
        tint: Color,
        domain: @escaping ([ChartSample]) -> ClosedRange<Double>,
        format: @escaping (Double) -> String
    ) -> some View {
        linked(card) {
            PulseCard {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        iconLabel(card.title, symbol: symbol, tint: tint)
                        reading(card)
                        caption(card)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: card.series == nil ? .infinity : 132, alignment: .leading)

                    if let series = card.series {
                        HistoryAnnotatedChart(annotation: card.seriesNote) {
                            SparklineChart(
                                samples: series,
                                tint: tint,
                                domain: domain(series),
                                formatY: format
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func fact(_ card: MachineOverview.Card, symbol: String, tint: Color) -> some View {
        linked(card) {
            PulseCard {
                VStack(alignment: .leading, spacing: 6) {
                    iconLabel(card.title, symbol: symbol, tint: tint)
                    reading(card)
                    if let percent = card.batteryPercent {
                        batteryBar(percent: percent, tint: tint)
                    }
                    caption(card)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func reading(_ card: MachineOverview.Card) -> some View {
        if let value = card.value {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let delta = card.delta {
                Text(delta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        } else {
            SkeletonBlock(width: 96, height: 28)
        }
    }

    @ViewBuilder
    private func caption(_ card: MachineOverview.Card) -> some View {
        if let caption = card.caption, !caption.isEmpty {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

    private func batteryBar(percent: Int, tint: Color) -> some View {
        GeometryReader { proxy in
            let fraction = CGFloat(min(max(percent, 0), 100)) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(tint).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func diagnostics(_ model: MachineOverview.Model) -> some View {
        PulseCard(padding: 12) {
            HStack(spacing: 12) {
                ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, item in
                    diagnostic(item)
                }
            }
        }
    }

    @ViewBuilder
    private func diagnostic(_ item: MachineOverview.Diagnostic) -> some View {
        if let page = item.page {
            Button {
                open(page)
            } label: {
                diagnosticLabel(item)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(diagnosticAccessibility(item, page: page))
            .accessibilityAddTraits(.isButton)
        } else {
            diagnosticLabel(item)
                .accessibilityElement(children: .combine)
        }
    }

    private func diagnosticLabel(_ item: MachineOverview.Diagnostic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(item.status)
                .font(.headline)
                .foregroundStyle(statusColor(item.status))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func linked<Content: View>(
        _ card: MachineOverview.Card,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let page = card.page {
            Button {
                open(page)
            } label: {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cardAccessibility(card, page: page))
            .accessibilityAddTraits(.isButton)
        } else {
            content()
                .accessibilityElement(children: .combine)
        }
    }

    private func open(_ page: MachineOverview.Page) {
        switch page {
        case .memory:
            vm.selectPage(.memory)
        case .cpu:
            vm.selectPage(.cpu)
        }
    }

    private func cardAccessibility(_ card: MachineOverview.Card, page: MachineOverview.Page) -> String {
        var value = card.value ?? card.caption ?? MachineStatusCopy.samplingCaption
        if let caption = card.caption, card.value != nil, caption != value {
            value += "，\(caption)"
        }
        if let delta = card.delta {
            value += "，\(delta)"
        }
        if let note = card.seriesNote {
            value += "，\(note)"
        }
        return MachineStatusCopy.buttonLabel(title: card.title, value: value, destination: destination(page))
    }

    private func ringAccessibility(_ ring: MachineOverview.Ring) -> String {
        let value = ring.label ?? MachineStatusCopy.samplingCaption
        return MachineStatusCopy.buttonLabel(title: "压力", value: value, destination: destination(ring.page))
    }

    private func diagnosticAccessibility(
        _ item: MachineOverview.Diagnostic,
        page: MachineOverview.Page
    ) -> String {
        MachineStatusCopy.buttonLabel(title: item.title, value: item.status, destination: destination(page))
    }

    private func destination(_ page: MachineOverview.Page) -> String {
        switch page {
        case .memory:
            return MachineStatusCopy.memoryDestination
        case .cpu:
            return MachineStatusCopy.cpuDestination
        }
    }

    private func ringTint(_ tone: MachineOverview.Ring.Tone) -> Color {
        switch tone {
        case .normal:
            return PulsePalette.pressureNormal
        case .elevated:
            return PulsePalette.pressureElevated
        case .sampling, .missing:
            return .secondary
        }
    }

    private func statusColor(_ status: String) -> Color {
        if status == PressureLevel.normal.title {
            return PulsePalette.pressureNormal
        }
        if status == PressureLevel.elevated.title {
            return PulsePalette.pressureElevated
        }
        return .primary
    }

    private func iconLabel(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
    }

    private func percentDomain(_ series: [ChartSample]) -> ClosedRange<Double> {
        let peak = series.map(\.value).max() ?? 0
        return 0...max(peak * 1.2, 5)
    }

    private func byteDomain(_ series: [ChartSample]) -> ClosedRange<Double> {
        let peak = series.map(\.value).max() ?? 0
        return 0...max(peak * 1.2, 1)
    }
}
