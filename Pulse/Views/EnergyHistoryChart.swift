import Charts
import SwiftUI

/// Process-sum curve for the energy page. Nil minutes break the line; they are not drawn as 0.
struct EnergyHistoryChart: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        PulseCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                legend
                if showsLine {
                    curves
                } else {
                    Text(HistoryCurvePresentation.unavailable)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var points: [EnergyHistoryPoint] {
        vm.energyMachineHistory.points
    }

    private var showsLine: Bool {
        points.compactMap(\.watts).count >= 2
    }

    private var showsBattery: Bool {
        vm.energyBatteryReading?.hasInternalBattery == true
    }

    private var accessibilityText: String {
        if showsLine {
            return showsBattery ? "进程能耗合计，电量" : "进程能耗合计"
        }
        return HistoryCurvePresentation.unavailable
    }

    private var legend: some View {
        HStack(spacing: 14) {
            key(PulsePalette.pressureElevated, "进程能耗合计")
            if showsBattery {
                key(PulsePalette.chartNetwork, "电量")
            }
            Spacer(minLength: 0)
        }
    }

    private func key(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 3)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var xDomain: ClosedRange<Date> {
        let first = points.first?.minuteStart ?? .distantPast
        let last = points.last?.minuteStart ?? first
        return first < last ? first...last : first...first.addingTimeInterval(60)
    }

    private var wattDomain: ClosedRange<Double> {
        let peak = points.compactMap(\.watts).max() ?? 1
        return 0...max(peak * 1.2, 1)
    }

    private var curves: some View {
        Chart {
            ForEach(segments(\.watts)) { segment in
                ForEach(segment.samples) { sample in
                    LineMark(
                        x: .value("时间", sample.date),
                        y: .value("进程能耗合计", sample.value),
                        series: .value("段", segment.id)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(PulsePalette.pressureElevated)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: wattDomain)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(ByteFormat.clock(date))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(ProcessEnergyText.watts(number))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                }
            }
            if showsBattery {
                AxisMarks(position: .trailing, values: [0.0]) { _ in
                    AxisValueLabel {
                        Text("100%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .hidden()
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if showsBattery, let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    batteryStroke(proxy: proxy, frame: frame)
                    percentLabels(frame: frame, width: geometry.size.width)
                }
            }
        }
    }

    private func batteryStroke(proxy: ChartProxy, frame: CGRect) -> some View {
        batteryPath(proxy: proxy, frame: frame)
            .stroke(
                PulsePalette.chartNetwork,
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
    }

    /// Percent uses the plot height, not the watt scale. A nil minute breaks the stroke.
    private func batteryPath(proxy: ChartProxy, frame: CGRect) -> Path {
        var path = Path()
        var drawing = false
        for point in points {
            guard let percent = point.batteryPercent,
                  let x = proxy.position(forX: point.minuteStart)
            else {
                drawing = false
                continue
            }
            let y = frame.maxY - CGFloat(percent / 100) * frame.height
            let next = CGPoint(x: x, y: y)
            if drawing {
                path.addLine(to: next)
            } else {
                path.move(to: next)
                drawing = true
            }
        }
        return path
    }

    private func percentLabels(frame: CGRect, width: CGFloat) -> some View {
        ForEach([0, 50, 100], id: \.self) { tick in
            Text("\(tick)%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
                .position(
                    x: width - 18,
                    y: frame.maxY - CGFloat(tick) / 100 * frame.height
                )
        }
    }

    /// A nil watt minute ends the series so the line does not bridge the gap.
    private func segments(_ value: (EnergyHistoryPoint) -> Double?) -> [CurveSegment] {
        var result: [CurveSegment] = []
        var current: [CurveSample] = []
        for point in points {
            if let sample = value(point) {
                current.append(CurveSample(date: point.minuteStart, value: sample))
            } else if !current.isEmpty {
                result.append(CurveSegment(id: "\(result.count)", samples: current))
                current = []
            }
        }
        if !current.isEmpty {
            result.append(CurveSegment(id: "\(result.count)", samples: current))
        }
        return result
    }
}

private struct CurveSample: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

private struct CurveSegment: Identifiable {
    let id: String
    let samples: [CurveSample]
}
