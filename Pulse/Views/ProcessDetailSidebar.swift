import AppKit
import Charts
import SwiftUI

struct ProcessDetailSidebar: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        Group {
            if let detail = vm.detail ?? selectedFallback {
                detailBody(detail)
            } else {
                AppEmptyState(
                    systemImage: "sidebar.right",
                    title: "未选择进程",
                    message: "在列表中点选一行，查看占用曲线并退出。"
                )
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var selectedFallback: ProcessDetail? {
        guard let row = vm.selectedRow else { return nil }
        return ProcessDetail(row: row, memorySeries: [], cpuSeries: [])
    }

    private func detailBody(_ detail: ProcessDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProcessIconView(pid: detail.row.pid, bundleIdentifier: detail.row.bundleIdentifier)
                    .scaleEffect(1.4)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.row.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text("PID \(detail.row.pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                metric(title: "内存", value: ByteFormat.memory(detail.row.memoryBytes))
                metric(title: "CPU", value: ByteFormat.cpu(detail.row.cpuPercent))
            }

            seriesBlock(
                title: "内存",
                samples: detail.memorySeries,
                placeholder: "正在采集内存曲线",
                unit: "字节",
                tint: PulsePalette.app,
                format: { ByteFormat.memory(UInt64($0)) }
            )
            .frame(height: 118)

            seriesBlock(
                title: "CPU",
                samples: detail.cpuSeries,
                placeholder: "正在采集 CPU 曲线",
                unit: "CPU",
                tint: PulsePalette.wired,
                format: { ByteFormat.cpu($0) }
            )
            .frame(height: 84)

            if let quitMessage = vm.quitMessage {
                Text(quitMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("退出") {
                    Task { await vm.quitSelected() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.quitPhase == .quitting)

                Button("强制退出") {
                    Task { await vm.forceQuitSelected() }
                }
                .buttonStyle(.bordered)
                .disabled(vm.quitPhase == .quitting)
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

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seriesBlock(
        title: String,
        samples: [ChartSample],
        placeholder: String,
        unit: String,
        tint: Color,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if samples.count < 2 {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(samples) { sample in
                    AreaMark(
                        x: .value("时间", sample.date),
                        y: .value(unit, sample.value)
                    )
                    .foregroundStyle(tint.opacity(0.16))
                    LineMark(
                        x: .value("时间", sample.date),
                        y: .value(unit, sample.value)
                    )
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(format(number))
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
    }
}
