import Foundation

extension MemoryDashboardVM {
    var historyCurveRange: HistoryCurveRange { core.historyCurveRange }

    func selectHistoryCurveRange(_ range: HistoryCurveRange) {
        mutateCore { $0.setHistoryCurveRange(range) }
        guard let query = range.query else { return }
        let end = Date()
        let start = end.addingTimeInterval(-query.duration)
        let samples = query.minute
            ? HistoryStore.shared.minuteSamples(from: start, to: end)
            : HistoryStore.shared.samples(from: start, to: end)
        let events = HistoryStore.shared.datedEvents(from: start, to: end)
        mutateCore { $0.replaceHistoryCurve(samples: samples, events: events, end: end) }
    }

    func historyCurvePlot(_ value: (HistorySample) -> Double?) -> HistoryCurvePlot? {
        core.historyCurvePlot(value)
    }
}
