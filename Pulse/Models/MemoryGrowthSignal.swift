import Foundation

/// Soft trend over one selected-process memory series (`ChartSample.value` is bytes).
///
/// The input is that series in sample order (the ring's append order). The whole array
/// is the window. Short series stay `.insufficient`. A full window is `.rising` only when
/// the net increase and the share of upward steps both clear the bars below; otherwise
/// `.none`. No slope fit, no host usage series, no other process.
enum MemoryGrowthSignal: Equatable, Sendable {
    /// Fewer than `minSamples` points. The window is still filling.
    case insufficient
    /// Net increase and a majority of adjacent steps are up.
    case rising
    /// The window is full, and the two rise conditions are not both met.
    case none

    /// Points required before a rise can be reported. A shorter prefix stays `.insufficient`.
    static let minSamples = 80

    /// Strict net byte increase from the first sample to the last.
    /// 8 MiB sits above megabyte-scale jitter without requiring a huge climb.
    static let deltaThreshold: Double = 8 * 1024 * 1024

    /// Minimum share of adjacent steps with a positive delta.
    /// Compared as 3/5 so the boundary is exact: `positiveSteps * 5 >= stepCount * 3`.
    static let riseFloor = 0.6

    private static let riseFloorNumerator = 3
    private static let riseFloorDenominator = 5

    static func evaluate(_ samples: [ChartSample]) -> MemoryGrowthSignal {
        guard samples.count >= minSamples else {
            return .insufficient
        }

        let netIncrease = samples[samples.count - 1].value - samples[0].value
        guard netIncrease > deltaThreshold else {
            return .none
        }

        let stepCount = samples.count - 1
        var positiveSteps = 0
        for index in 1..<samples.count where samples[index].value > samples[index - 1].value {
            positiveSteps += 1
        }
        guard positiveSteps * riseFloorDenominator >= stepCount * riseFloorNumerator else {
            return .none
        }
        return .rising
    }
}

/// Locked memory-page sidebar copy. The title is a trend label, never a leak verdict.
enum MemoryGrowthCopy {
    static let title = "内存趋势"
    static let rising = "近几分钟持续上涨"
    static let insufficient = "样本不足，暂不判断"

    static func caption(for signal: MemoryGrowthSignal) -> String? {
        switch signal {
        case .rising:
            return rising
        case .insufficient:
            return insufficient
        case .none:
            return nil
        }
    }
}

/// One visible sidebar slot. Absence means the view renders nothing.
struct MemoryGrowthSlot: Equatable, Sendable {
    let title: String
    let caption: String
}

/// Memory-page detail sidebar only. CPU and the other pages stay silent.
enum MemoryGrowthSidebar {
    /// `selectedPid == nil` clears the slot even if a previous series is still passed in.
    /// A live selection with `detailSeries == nil` (detail just cleared) evaluates an empty
    /// window, so the result is insufficient rather than the previous process's rising line.
    static func slot(
        page: DashboardPage,
        selectedPid: Int32?,
        detailSeries: [ChartSample]?
    ) -> MemoryGrowthSlot? {
        guard page == .memory, selectedPid != nil else { return nil }
        let signal = MemoryGrowthSignal.evaluate(detailSeries ?? [])
        guard let caption = MemoryGrowthCopy.caption(for: signal) else { return nil }
        return MemoryGrowthSlot(title: MemoryGrowthCopy.title, caption: caption)
    }
}

/// Locked memory-tab list-row copy. Short badge, calm hover; never a leak verdict.
enum MemoryGrowthListCopy {
    static let title = "上涨"
    static let help = "近期内存持续上涨"
}

/// Visible list badge. Absence means the row paints nothing in the badge slot.
struct MemoryGrowthListBadge: Equatable, Sendable {
    let title: String
    let help: String
}

/// Memory-page selected-row list only. Other tabs and unselected rows stay silent.
enum MemoryGrowthList {
    /// Only `.rising` returns a badge. Insufficient / none / unselected / other pages are `nil`.
    /// Does not reuse sidebar insufficient copy — the list slot stays empty.
    static func badge(
        page: DashboardPage,
        rowPid: Int32,
        selectedPid: Int32?,
        detailSeries: [ChartSample]?
    ) -> MemoryGrowthListBadge? {
        guard page == .memory, selectedPid == rowPid else { return nil }
        guard MemoryGrowthSignal.evaluate(detailSeries ?? []) == .rising else { return nil }
        return MemoryGrowthListBadge(title: MemoryGrowthListCopy.title, help: MemoryGrowthListCopy.help)
    }

    /// Phase-9 density predicate. `seriesByPid` only holds current Top 5 series.
    /// Missing / insufficient / none / other pages stay `nil`. Same `evaluate` as the sidebar.
    static func badge(
        page: DashboardPage,
        rowPid: Int32,
        seriesByPid: [Int32: [ChartSample]]
    ) -> MemoryGrowthListBadge? {
        guard page == .memory, let series = seriesByPid[rowPid] else { return nil }
        guard MemoryGrowthSignal.evaluate(series) == .rising else { return nil }
        return MemoryGrowthListBadge(title: MemoryGrowthListCopy.title, help: MemoryGrowthListCopy.help)
    }
}
