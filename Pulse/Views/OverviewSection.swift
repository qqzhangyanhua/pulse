import Charts
import SwiftUI

struct OverviewSection: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        Group {
            switch vm.loadState {
            case .sampling:
                samplingBody
            case .failed:
                AppEmptyState(
                    systemImage: "waveform.path.ecg",
                    title: "暂时无法读取内存数据",
                    message: "采样没有返回可用快照。不会用 0 填充总览。",
                    retryTitle: "重新采样",
                    onRetry: vm.retrySampling
                )
                .frame(minHeight: 168)
            case .ready:
                if let snapshot = vm.snapshot {
                    readyBody(snapshot)
                } else {
                    AppEmptyState(
                        systemImage: "waveform.path.ecg",
                        title: "暂时无法读取内存数据",
                        message: "快照为空，未写入用量数字。",
                        retryTitle: "重新采样",
                        onRetry: vm.retrySampling
                    )
                    .frame(minHeight: 168)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private var samplingBody: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("正在采集内存数据…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SkeletonBlock(width: 220, height: 36)
                SkeletonBlock(height: 10)
                HStack {
                    SkeletonBlock(width: 64, height: 12)
                    SkeletonBlock(width: 64, height: 12)
                    SkeletonBlock(width: 88, height: 12)
                    SkeletonBlock(width: 72, height: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: 72, height: 22)
                SkeletonBlock(height: 72)
            }
            .frame(width: 280, alignment: .leading)
        }
        .frame(minHeight: 148)
    }

    private func readyBody(_ snapshot: MemorySnapshot) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("内存用量")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ByteFormat.memory(snapshot.usedBytes))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("/ \(ByteFormat.memory(snapshot.totalBytes))")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                CategoryBar(breakdown: snapshot.breakdown, totalBytes: snapshot.totalBytes)
                    .frame(height: 10)
                    .padding(.top, 4)
                CategoryLegend(breakdown: snapshot.breakdown)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PressureCard(snapshot: snapshot)
                .frame(width: 300, alignment: .leading)
        }
    }
}

struct CategoryBar: View {
    let breakdown: MemoryBreakdown
    let totalBytes: UInt64

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let total = max(totalBytes, 1)
            HStack(spacing: 1) {
                segment(bytes: breakdown.appBytes, color: PulsePalette.app, width: width, total: total)
                segment(bytes: breakdown.wiredBytes, color: PulsePalette.wired, width: width, total: total)
                segment(bytes: breakdown.compressedBytes, color: PulsePalette.compressed, width: width, total: total)
                segment(bytes: breakdown.cachedBytes, color: PulsePalette.cached, width: width, total: total)
                Spacer(minLength: 0)
            }
        }
        .background(Color.primary.opacity(0.06))
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

struct CategoryLegend: View {
    let breakdown: MemoryBreakdown

    var body: some View {
        HStack(spacing: 14) {
            legend(color: PulsePalette.app, title: "App", bytes: breakdown.appBytes)
            legend(color: PulsePalette.wired, title: "Wired", bytes: breakdown.wiredBytes)
            legend(color: PulsePalette.compressed, title: "Compressed", bytes: breakdown.compressedBytes)
            legend(color: PulsePalette.cached, title: "Cached", bytes: breakdown.cachedBytes)
            Spacer(minLength: 0)
        }
    }

    private func legend(color: Color, title: String, bytes: UInt64) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(ByteFormat.memory(bytes))
                .monospacedDigit()
        }
        .font(.caption)
    }
}

struct PressureCard: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tone)
                    .frame(width: 8, height: 8)
                Text(snapshot.pressure.title)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
            }
            Text(snapshot.pressure.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if snapshot.pressureSeries.count < 2 {
                Text("压力曲线采集中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 72, alignment: .center)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(snapshot.pressureSeries) { sample in
                    AreaMark(
                        x: .value("时间", sample.date),
                        y: .value("压力", sample.value)
                    )
                    .foregroundStyle(tone.opacity(0.18))
                    LineMark(
                        x: .value("时间", sample.date),
                        y: .value("压力", sample.value)
                    )
                    .foregroundStyle(tone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: 0...1)
                .chartYAxis(.hidden)
                .frame(height: 72)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var tone: Color {
        snapshot.pressure == .normal ? PulsePalette.pressureNormal : PulsePalette.pressureElevated
    }
}
