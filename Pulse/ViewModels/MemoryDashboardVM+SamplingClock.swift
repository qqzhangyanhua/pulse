import Foundation

extension MemoryDashboardVM {
    func nanosecondsElapsed(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> UInt64 {
        let duration = start.duration(to: end)
        let seconds = duration.components.seconds
        let attoseconds = duration.components.attoseconds
        if seconds < 0 { return 0 }
        let secNanos = UInt64(seconds) &* 1_000_000_000
        let nanoPart = attoseconds <= 0 ? 0 : UInt64(attoseconds / 1_000_000_000)
        return secNanos &+ nanoPart
    }
}
