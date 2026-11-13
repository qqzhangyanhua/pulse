import Foundation

extension DashboardCore {
    mutating func setHistoryCurveRange(_ range: HistoryCurveRange) -> [DashboardEffect] {
        historyCurveRange = range
        if range == .live {
            historyCurveSamples = []
            historyCurveEvents = []
            historyCurveEnd = nil
        }
        return []
    }

    mutating func replaceHistoryCurve(
        samples: [HistorySample],
        events: [HistoryStoredEvent],
        end: Date
    ) -> [DashboardEffect] {
        guard historyCurveRange != .live else { return [] }
        historyCurveSamples = samples
        historyCurveEvents = events
        historyCurveEnd = end
        return []
    }

    func historyCurvePlot(_ value: (HistorySample) -> Double?) -> HistoryCurvePlot? {
        guard let query = historyCurveRange.query, let end = historyCurveEnd else { return nil }
        let start = end.addingTimeInterval(-query.duration)
        let points = query.minute
            ? HistoryCurveSeries.buckets(
                samples: historyCurveSamples,
                from: start,
                to: end,
                step: 60,
                value: value
            )
            : HistoryCurveSeries.raw(
                samples: historyCurveSamples,
                from: start,
                to: end,
                value: value
            )
        return HistoryCurvePlot(points: points, marks: HistoryCurveSeries.marks(historyCurveEvents))
    }
}
