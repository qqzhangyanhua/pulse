enum HistoryCurvePresentation {
    static let unavailable = "历史曲线 · 当前值暂不可用"

    static func annotation(current: Double?, sampleCount: Int) -> String? {
        guard current == nil, sampleCount >= 2 else { return nil }
        return unavailable
    }
}
