import Charts
import SwiftUI

struct HistoryRangeControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let range: HistoryCurveRange
    let select: (HistoryCurveRange) -> Void

    var body: some View {
        Picker("曲线范围", selection: Binding(get: { range }, set: select)) {
            ForEach(HistoryCurveRange.allCases, id: \.self) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("曲线范围")
        .animation(reduceMotion ? nil : PulseMotion.page, value: range)
    }
}

/// Non-live curve. A nil value breaks the line. Event marks keep their own labels.
struct HistoryRangeChart: View {
    let plot: HistoryCurvePlot
    var tint: Color
    var domain: ClosedRange<Double>
    var formatY: (Double) -> String

    var body: some View {
        Chart {
            ForEach(segments) { segment in
                ForEach(segment.points) { point in
                    if let value = point.value {
                        LineMark(
                            x: .value("时间", point.at),
                            y: .value("值", value),
                            series: .value("段", segment.id)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(tint)
                        AreaMark(
                            x: .value("时间", point.at),
                            y: .value("值", value),
                            series: .value("段", segment.id)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(tint.opacity(0.18))
                    }
                }
            }
            ForEach(plot.marks) { mark in
                RuleMark(x: .value("时间", mark.at))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .accessibilityLabel(mark.label)
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: domain)
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
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatY(number))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                }
            }
        }
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var current: [HistoryCurvePoint] = []
        func close() {
            guard !current.isEmpty else { return }
            result.append(Segment(id: result.count, points: current))
            current = []
        }
        for point in plot.points {
            if point.value == nil {
                close()
            } else {
                current.append(point)
            }
        }
        close()
        return result
    }

    private struct Segment: Identifiable {
        var id: Int
        var points: [HistoryCurvePoint]
    }
}

/// Stored curve, or the live sparkline once two samples exist. The live path keeps the current-value note.
struct HistoryRateChart: View {
    var history: HistoryCurvePlot?
    let samples: [ChartSample]
    var rate: Double?
    var tint: Color
    var domain: ClosedRange<Double>
    var placeholder: String
    var formatY: (Double) -> String

    var body: some View {
        if let history {
            HistoryRangeChart(
                plot: history,
                tint: tint,
                domain: domain,
                formatY: formatY
            )
        } else if samples.count < 2 {
            ChartPlaceholder(text: placeholder)
        } else {
            HistoryAnnotatedChart(
                annotation: HistoryCurvePresentation.annotation(current: rate, sampleCount: samples.count)
            ) {
                SparklineChart(
                    samples: samples,
                    tint: tint,
                    domain: domain,
                    formatY: formatY
                )
            }
        }
    }
}
