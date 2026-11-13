import XCTest
@testable import SamplingCore

/// Literals are the memory-pressure notice frames. They matched `PressureNotice.advance`
/// before that type was removed.
final class AlertRuleTests: XCTestCase {
    func testBuiltinMemoryPressureMatchesPressureNoticeOnTheSameFrames() {
        let table: [(start: AlertRule.State.Phase, frames: [Frame])] = [
            (
                .armed,
                [Frame("first elevated sends", .elevated, 1_700_000_000, send: true, .fired(clearSince: nil))]
            ),
            (
                .fired(clearSince: at(1_700_000_100)),
                [Frame("elevated while fired stays quiet", .elevated, 1_700_000_120, send: false, .fired(clearSince: nil))]
            ),
            (
                .armed,
                [
                    Frame("episode starts", .elevated, 1_700_000_000, send: true, .fired(clearSince: nil)),
                    Frame("normal starts the streak", .normal, 1_700_000_100, send: false, .fired(clearSince: at(1_700_000_100))),
                    Frame("299 seconds does not rearm", .normal, 1_700_000_399, send: false, .fired(clearSince: at(1_700_000_100))),
                    Frame("300 seconds rearms", .normal, 1_700_000_400, send: false, .armed),
                    Frame("the next elevated sends again", .elevated, 1_700_000_401, send: true, .fired(clearSince: nil)),
                ]
            ),
            (
                .armed,
                [Frame("nil while armed changes nothing", nil, 1_700_000_000, send: false, .armed)]
            ),
            (
                .fired(clearSince: at(1_700_000_100)),
                [
                    Frame("nil does not finish the streak", nil, 1_700_000_400, send: false, .fired(clearSince: at(1_700_000_100))),
                    Frame("the same instant of normal still counts from the streak", .normal, 1_700_000_400, send: false, .armed),
                ]
            ),
            (
                .fired(clearSince: at(1_700_000_100)),
                [
                    Frame("elevated clears the streak", .elevated, 1_700_000_200, send: false, .fired(clearSince: nil)),
                    Frame("normal starts over", .normal, 1_700_000_210, send: false, .fired(clearSince: at(1_700_000_210))),
                    Frame("299 seconds from the restart stays fired", .normal, 1_700_000_509, send: false, .fired(clearSince: at(1_700_000_210))),
                ]
            ),
            (
                .armed,
                [Frame("normal while armed does not send", .normal, 1_700_000_000, send: false, .armed)]
            ),
            (
                .armed,
                [Frame("switch off does not send", .elevated, 1_700_000_000, send: false, .armed, enabled: false)]
            ),
            (
                .fired(clearSince: at(1_700_000_100)),
                [Frame("switch off does not rearm", .normal, 1_700_000_400, send: false, .fired(clearSince: at(1_700_000_100)), enabled: false)]
            ),
            (
                .armed,
                [
                    Frame("one episode sends", .elevated, 1_700_000_000, send: true, .fired(clearSince: nil)),
                    Frame("thirty more minutes of elevated still does not send", .elevated, 1_700_001_800, send: false, .fired(clearSince: nil)),
                ]
            ),
        ]

        for row in table {
            assertBuiltinMatches(start: row.start, row.frames)
        }
    }

    func testBuiltinKeepsThePressureNoticeKeyAndDefaultsOn() {
        XCTAssertEqual(AlertRule.memoryPressure.id, "pulse.pressureNotice")
        XCTAssertEqual(PressureNoticePreference.defaultsKey, "pulse.pressureNotice")
        XCTAssertEqual(AlertRule.memoryPressure.rearm, 300)
        XCTAssertEqual(AlertRule.memoryPressure.cooldown, 0)
        XCTAssertNil(AlertRule.memoryPressure.dailyLimit)
        XCTAssertTrue(AlertRule.memoryPressure.builtin)

        let suite = "pulse.pressureNotice.alertRule"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertTrue(PressureNoticePreference.isEnabled(in: defaults))
        defaults.set(false, forKey: "pulse.pressureNotice")
        XCTAssertFalse(PressureNoticePreference.isEnabled(in: defaults))
        defaults.set(true, forKey: "pulse.pressureNotice")
        XCTAssertTrue(PressureNoticePreference.isEnabled(in: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    func testCooldownHoldsTheNextEpisodeAndDoesNotRepeatWhileElevated() {
        let rule = AlertRule(
            id: "custom.cooldown",
            builtin: false,
            rearm: 300,
            cooldown: 1_800,
            dailyLimit: nil
        )
        let sent = rule.advance(
            enabled: true,
            state: .armed,
            pressure: .elevated,
            at: at(1_700_000_000)
        )
        XCTAssertTrue(sent.send)
        XCTAssertEqual(sent.state.phase, .fired(clearSince: nil))
        XCTAssertEqual(sent.state.cooldownUntil, at(1_700_001_800))

        let stillElevated = rule.advance(
            enabled: true,
            state: sent.state,
            pressure: .elevated,
            at: at(1_700_001_800)
        )
        XCTAssertFalse(stillElevated.send)
        XCTAssertEqual(stillElevated.state.phase, .fired(clearSince: nil))

        let clearing = rule.advance(
            enabled: true,
            state: sent.state,
            pressure: .normal,
            at: at(1_700_000_100)
        )
        XCTAssertFalse(clearing.send)
        XCTAssertEqual(clearing.state.phase, .fired(clearSince: at(1_700_000_100)))

        let rearmed = rule.advance(
            enabled: true,
            state: clearing.state,
            pressure: .normal,
            at: at(1_700_000_400)
        )
        XCTAssertFalse(rearmed.send)
        XCTAssertEqual(rearmed.state.phase, .armed)
        XCTAssertEqual(rearmed.state.cooldownUntil, at(1_700_001_800))

        let skipped = rule.advance(
            enabled: true,
            state: rearmed.state,
            pressure: nil,
            at: at(1_700_001_000)
        )
        XCTAssertFalse(skipped.send)
        XCTAssertEqual(skipped.state, rearmed.state)

        let early = rule.advance(
            enabled: true,
            state: rearmed.state,
            pressure: .elevated,
            at: at(1_700_001_799)
        )
        XCTAssertFalse(early.send)
        XCTAssertEqual(early.state.phase, .armed)
        XCTAssertEqual(early.state.cooldownUntil, at(1_700_001_800))

        let due = rule.advance(
            enabled: true,
            state: early.state,
            pressure: .elevated,
            at: at(1_700_001_800)
        )
        XCTAssertTrue(due.send)
        XCTAssertEqual(due.state.phase, .fired(clearSince: nil))
        XCTAssertEqual(due.state.cooldownUntil, at(1_700_003_600))
    }

    func testDailyLimitBlocksAnotherEpisodeUntilTheNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rule = AlertRule(
            id: "custom.daily",
            builtin: false,
            rearm: 0,
            cooldown: 0,
            dailyLimit: 1
        )
        let day = TimeInterval(1_704_067_200)
        let first = rule.advance(
            enabled: true,
            state: .armed,
            pressure: .elevated,
            at: at(day),
            calendar: calendar
        )
        XCTAssertTrue(first.send)
        XCTAssertEqual(first.state.phase, .fired(clearSince: nil))
        XCTAssertEqual(first.state.sendsOnDay, 1)
        XCTAssertEqual(first.state.dayStart, at(day))

        let cleared = rule.advance(
            enabled: true,
            state: first.state,
            pressure: .normal,
            at: at(day + 1),
            calendar: calendar
        )
        XCTAssertFalse(cleared.send)
        XCTAssertEqual(cleared.state.phase, .armed)
        XCTAssertEqual(cleared.state.sendsOnDay, 1)

        let blocked = rule.advance(
            enabled: true,
            state: cleared.state,
            pressure: .elevated,
            at: at(day + 86_399),
            calendar: calendar
        )
        XCTAssertFalse(blocked.send)
        XCTAssertEqual(blocked.state.phase, .armed)
        XCTAssertEqual(blocked.state.sendsOnDay, 1)
        XCTAssertEqual(blocked.state.dayStart, at(day))

        let held = rule.advance(
            enabled: false,
            state: blocked.state,
            pressure: .elevated,
            at: at(day + 86_400),
            calendar: calendar
        )
        XCTAssertFalse(held.send)
        XCTAssertEqual(held.state, blocked.state)

        let nextDay = rule.advance(
            enabled: true,
            state: blocked.state,
            pressure: .elevated,
            at: at(day + 86_400),
            calendar: calendar
        )
        XCTAssertTrue(nextDay.send)
        XCTAssertEqual(nextDay.state.phase, .fired(clearSince: nil))
        XCTAssertEqual(nextDay.state.sendsOnDay, 1)
        XCTAssertEqual(nextDay.state.dayStart, at(day + 86_400))
    }

    private struct Frame {
        var label: String
        var enabled: Bool
        var pressure: PressureLevel?
        var at: TimeInterval
        var send: Bool
        var phase: AlertRule.State.Phase

        init(
            _ label: String,
            _ pressure: PressureLevel?,
            _ at: TimeInterval,
            send: Bool,
            _ phase: AlertRule.State.Phase,
            enabled: Bool = true
        ) {
            self.label = label
            self.enabled = enabled
            self.pressure = pressure
            self.at = at
            self.send = send
            self.phase = phase
        }
    }

    private func assertBuiltinMatches(
        start: AlertRule.State.Phase,
        _ frames: [Frame],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var ruleState = AlertRule.State(phase: start)
        for frame in frames {
            let decision = AlertRule.memoryPressure.advance(
                enabled: frame.enabled,
                state: ruleState,
                pressure: frame.pressure,
                at: Date(timeIntervalSince1970: frame.at)
            )
            XCTAssertEqual(decision.send, frame.send, frame.label, file: file, line: line)
            XCTAssertEqual(decision.state.phase, frame.phase, frame.label, file: file, line: line)
            XCTAssertNil(decision.state.cooldownUntil, frame.label, file: file, line: line)
            XCTAssertEqual(decision.state.sendsOnDay, 0, frame.label, file: file, line: line)
            XCTAssertNil(decision.state.dayStart, frame.label, file: file, line: line)
            ruleState = decision.state
        }
    }

    private func at(_ time: TimeInterval) -> Date {
        Date(timeIntervalSince1970: time)
    }
}
