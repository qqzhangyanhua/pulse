import SwiftUI

extension ProcessDetailSidebar {
    /// Memory page only. Other pages pass nil, so the shared card stays unlabeled.
    func memoryMagnitudeAttribution(displayed: ProcessRow, curve: ProcessRow, points: Int) -> String? {
        guard vm.selectedPage == .memory else { return nil }
        return MemoryDetailAttribution.make(
            page: vm.selectedPage,
            magnitudeRow: displayed,
            curveRow: curve,
            memoryPointCount: points,
            trendIsRising: false
        ).magnitude
    }

    func memoryTrend(_ slot: MemoryGrowthSlot, curveRow: ProcessRow) -> some View {
        // The slot caption is already the rise result. Point count does not choose this sentence.
        let trend = MemoryDetailAttribution.make(
            page: vm.selectedPage,
            magnitudeRow: curveRow,
            curveRow: curveRow,
            memoryPointCount: 0,
            trendIsRising: slot.caption == MemoryGrowthCopy.rising
        ).trend
        return VStack(alignment: .leading, spacing: 2) {
            Text(slot.title)
                .font(.caption.weight(.semibold))
            Text(slot.caption)
                .font(.caption)
            if let basis = slot.basis {
                Text(basis)
                    .font(.caption)
            }
            if let trend {
                Text(trend)
                    .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    func memoryChart(_ detail: ProcessDetail) -> some View {
        let attribution = MemoryDetailAttribution.make(
            page: vm.selectedPage,
            magnitudeRow: displayedMemoryRow(detail.row),
            curveRow: detail.row,
            memoryPointCount: detail.memorySeries.count,
            trendIsRising: false
        )
        let title: String
        if vm.selectedPage == .memory, let curveTitle = attribution.curveTitle {
            title = curveTitle
        } else {
            title = memoryField(displayedMemoryRow(detail.row)).title
        }
        return seriesBlock(
            title: title,
            samples: detail.memorySeries,
            placeholder: "正在采集内存曲线",
            summary: MemoryDetailAttribution.curveSummary(
                pidLine: vm.selectedPage == .memory ? attribution.curvePid : nil,
                recentAndPeak: memorySummary(detail.memorySeries)
            ),
            tint: PulsePalette.accent,
            domain: byteDomain(detail.memorySeries),
            formatY: { ByteFormat.memory(UInt64(max(0, $0))) },
            summaryScale: 0.65
        )
    }

    private func memorySummary(_ samples: [ChartSample]) -> String {
        guard let latest = samples.seriesLatest, let peak = samples.seriesPeak else { return "" }
        return "最近 \(ByteFormat.memory(UInt64(max(0, latest)))) · 峰值 \(ByteFormat.memory(UInt64(max(0, peak))))"
    }

    private func byteDomain(_ samples: [ChartSample]) -> ClosedRange<Double> {
        let peak = samples.map(\.value).max() ?? 0
        return 0...max(peak * 1.15, 1)
    }
}
