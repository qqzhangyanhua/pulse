import SwiftUI

struct TopConsumer: Equatable {
    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let memoryBytes: UInt64
    let processCount: Int
    static func leading(in rows: [ProcessRow]) -> TopConsumer? {
        struct Bucket {
            var pid: Int32
            var bundleIdentifier: String?
            var memoryBytes: UInt64
            var bestMemory: UInt64
            var processCount: Int
        }

        var buckets: [String: Bucket] = [:]
        for row in rows {
            var bucket = buckets[row.name] ?? Bucket(
                pid: row.pid,
                bundleIdentifier: row.bundleIdentifier,
                memoryBytes: 0,
                bestMemory: 0,
                processCount: 0
            )
            bucket.memoryBytes &+= row.memoryBytes
            bucket.processCount += 1
            if row.memoryBytes >= bucket.bestMemory {
                bucket.bestMemory = row.memoryBytes
                bucket.pid = row.pid
                bucket.bundleIdentifier = row.bundleIdentifier
            }
            buckets[row.name] = bucket
        }

        guard let best = buckets.max(by: { $0.value.memoryBytes < $1.value.memoryBytes }) else {
            return nil
        }
        return TopConsumer(
            pid: best.value.pid,
            name: best.key,
            bundleIdentifier: best.value.bundleIdentifier,
            memoryBytes: best.value.memoryBytes,
            processCount: best.value.processCount
        )
    }
}

struct MemoryHeroCard: View {
    let snapshot: MemorySnapshot
    let usedSeries: [ChartSample]
    var thermalNotice: String? = nil

    var body: some View {
        PulseCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(PulsePalette.accent.opacity(0.22))
                            .frame(width: 22, height: 22)
                            .overlay {
                                Image(systemName: "memorychip")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(PulsePalette.accent)
                            }
                        Text("内存")
                            .font(.subheadline.weight(.medium))
                    }
                    Text(ByteFormat.memory(snapshot.usedBytes))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("已使用，共 \(ByteFormat.gibWhole(snapshot.totalBytes))")
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

    @ViewBuilder
    private var chart: some View {
        if usedSeries.count < 2 {
            ChartPlaceholder(text: "用量曲线采集中")
        } else {
            SparklineChart(
                samples: usedSeries,
                tint: PulsePalette.accent,
                domain: domain,
                formatY: { ByteFormat.memory(UInt64(max(0, $0))) }
            )
        }
    }

    private var domain: ClosedRange<Double> {
        let peak = usedSeries.map(\.value).max() ?? 0
        let upper = max(Double(snapshot.totalBytes), peak, 1)
        return 0...upper
    }
}

struct CompositionCard: View {
    let breakdown: MemoryBreakdown
    let totalBytes: UInt64

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("按类型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CategoryBar(breakdown: breakdown)
                    .frame(height: 8)
                VStack(alignment: .leading, spacing: 6) {
                    CategoryLegendRow(color: PulsePalette.app, title: "App", bytes: breakdown.appBytes, totalBytes: totalBytes)
                    CategoryLegendRow(color: PulsePalette.wired, title: "联动", bytes: breakdown.wiredBytes, totalBytes: totalBytes)
                    CategoryLegendRow(color: PulsePalette.compressed, title: "被压缩", bytes: breakdown.compressedBytes, totalBytes: totalBytes)
                    CategoryLegendRow(color: PulsePalette.cached, title: "已缓存", bytes: breakdown.cachedBytes, totalBytes: totalBytes)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct CategoryBar: View {
    let breakdown: MemoryBreakdown

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let total = max(breakdown.categorizedBytes, 1)
            HStack(spacing: 1) {
                segment(bytes: breakdown.appBytes, color: PulsePalette.app, width: width, total: total)
                segment(bytes: breakdown.wiredBytes, color: PulsePalette.wired, width: width, total: total)
                segment(bytes: breakdown.compressedBytes, color: PulsePalette.compressed, width: width, total: total)
                segment(bytes: breakdown.cachedBytes, color: PulsePalette.cached, width: width, total: total)
                Spacer(minLength: 0)
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func segment(bytes: UInt64, color: Color, width: CGFloat, total: UInt64) -> some View {
        let fraction = CGFloat(bytes) / CGFloat(total)
        if fraction > 0 {
            color.frame(width: max(2, width * fraction))
        }
    }
}

struct CategoryLegendRow: View {
    let color: Color
    let title: String
    let bytes: UInt64
    let totalBytes: UInt64

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(ByteFormat.memory(bytes))
                .monospacedDigit()
                .lineLimit(1)
            Text(ByteFormat.wholePercent(part: bytes, total: totalBytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .font(.caption2)
    }
}

struct CategoryBarsCard: View {
    let breakdown: MemoryBreakdown
    let totalBytes: UInt64

    var body: some View {
        PulseCard {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("按类型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    bar(breakdown.appBytes, PulsePalette.app)
                    bar(breakdown.wiredBytes, PulsePalette.wired)
                    bar(breakdown.compressedBytes, PulsePalette.compressed)
                    bar(breakdown.cachedBytes, PulsePalette.cached)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    CategoryLegendRow(color: PulsePalette.app, title: "App", bytes: breakdown.appBytes, totalBytes: totalBytes)
                    CategoryLegendRow(color: PulsePalette.wired, title: "联动", bytes: breakdown.wiredBytes, totalBytes: totalBytes)
                    CategoryLegendRow(color: PulsePalette.compressed, title: "被压缩", bytes: breakdown.compressedBytes, totalBytes: totalBytes)
                    CategoryLegendRow(color: PulsePalette.cached, title: "已缓存", bytes: breakdown.cachedBytes, totalBytes: totalBytes)
                }
                .frame(width: 176)
            }
        }
    }

    private var maxBytes: UInt64 {
        [breakdown.appBytes, breakdown.wiredBytes, breakdown.compressedBytes, breakdown.cachedBytes].max() ?? 1
    }

    private func bar(_ bytes: UInt64, _ color: Color) -> some View {
        GeometryReader { proxy in
            let fraction = CGFloat(bytes) / CGFloat(maxBytes)
            Capsule()
                .fill(color)
                .frame(width: max(bytes > 0 ? 4 : 0, proxy.size.width * fraction), height: 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 8)
    }
}

struct PressureCurveCard: View {
    let snapshot: MemorySnapshot

    private var tone: Color {
        snapshot.pressure == .elevated ? PulsePalette.pressureElevated : PulsePalette.accent
    }

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Label("内存压力", systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let average = snapshot.pressureSeries.seriesAverage {
                            Text("平均 \(ByteFormat.wholePercent(value: average))")
                        }
                        if let peak = snapshot.pressureSeries.seriesPeak {
                            Text("峰值 \(ByteFormat.wholePercent(value: peak))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if snapshot.pressureSeries.count < 2 {
                    ChartPlaceholder(text: "压力曲线采集中")
                } else {
                    SparklineChart(
                        samples: snapshot.pressureSeries,
                        tint: tone,
                        domain: 0...1,
                        formatY: { ByteFormat.wholePercent(value: $0) }
                    )
                }
            }
        }
    }
}

struct MetricStatCard: View {
    let systemImage: String
    let title: String
    let value: String
    var valueColor: Color = .primary
    var caption: String
    var iconColor: Color = .secondary
    var border: Color = PulsePalette.hairline

    var body: some View {
        PulseCard(padding: 12, border: border) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(iconColor)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

struct PressureLevelCard: View {
    let snapshot: MemorySnapshot

    private var tone: Color {
        snapshot.pressure == .elevated ? PulsePalette.pressureElevated : PulsePalette.pressureNormal
    }

    var body: some View {
        MetricStatCard(
            systemImage: "gauge.medium",
            title: "压力",
            value: snapshot.pressure.title,
            valueColor: tone,
            caption: snapshot.pressure == .normal
                ? "\(Int((snapshot.pressureMetric * 100).rounded()))% · \(snapshot.pressure.caption)"
                : snapshot.pressure.caption,
            iconColor: tone,
            border: tone.opacity(snapshot.pressure == .elevated ? 0.55 : 0.16)
        )
    }
}

struct TopAppCard: View {
    let consumer: TopConsumer?
    var onSelect: (Int32) -> Void

    var body: some View {
        PulseCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.78, green: 0.66, blue: 0.98))
                    Text("占用最多的 App")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let consumer {
                    HStack(spacing: 8) {
                        ProcessIconView(
                            pid: consumer.pid,
                            bundleIdentifier: consumer.bundleIdentifier,
                            size: 22
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(consumer.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(ByteFormat.memory(consumer.memoryBytes)) · \(consumer.processCount) 个进程")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("—")
                        .font(.system(size: 22, weight: .semibold))
                    Text("暂无进程")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if let consumer {
                onSelect(consumer.pid)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityName)
    }
    private var accessibilityName: String {
        guard let consumer else { return "占用最多的 App，暂无进程" }
        return "占用最多的 App \(consumer.name)，\(ByteFormat.memory(consumer.memoryBytes))"
    }
}
