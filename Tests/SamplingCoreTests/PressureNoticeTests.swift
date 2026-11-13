import XCTest
@testable import SamplingCore

final class PressureNoticeTests: XCTestCase {
    func testFirstElevatedFrameWhileArmedSendsAndFires() {
        let decision = AlertRule.memoryPressure.advance(
            enabled: true,
            state: .armed,
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(decision.send)
        XCTAssertEqual(decision.state.phase, .fired(clearSince: nil))
    }

    func testElevatedWhileFiredDoesNotSendAndClearsTheNormalStreak() {
        let streak = Date(timeIntervalSince1970: 1_700_000_100)
        let decision = AlertRule.memoryPressure.advance(
            enabled: true,
            state: fired(clearSince: streak),
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_120)
        )
        XCTAssertFalse(decision.send)
        XCTAssertEqual(decision.state.phase, .fired(clearSince: nil))
    }

    func testFiveMinutesOfContinuousNormalRearmsAndAShorterGapDoesNot() {
        let fired = AlertRule.memoryPressure.advance(
            enabled: true,
            state: .armed,
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let started = AlertRule.memoryPressure.advance(
            enabled: true,
            state: fired.state,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_100)
        )
        XCTAssertFalse(started.send)
        XCTAssertEqual(started.state.phase, .fired(clearSince: Date(timeIntervalSince1970: 1_700_000_100)))

        let short = AlertRule.memoryPressure.advance(
            enabled: true,
            state: started.state,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_399)
        )
        XCTAssertFalse(short.send)
        XCTAssertEqual(short.state.phase, .fired(clearSince: Date(timeIntervalSince1970: 1_700_000_100)))

        let rearmed = AlertRule.memoryPressure.advance(
            enabled: true,
            state: short.state,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_400)
        )
        XCTAssertFalse(rearmed.send)
        XCTAssertEqual(rearmed.state.phase, .armed)

        let again = AlertRule.memoryPressure.advance(
            enabled: true,
            state: rearmed.state,
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_401)
        )
        XCTAssertTrue(again.send)
        XCTAssertEqual(again.state.phase, .fired(clearSince: nil))
    }

    func testNilFrameDoesNotSendOrResetPhase() {
        let armed = AlertRule.memoryPressure.advance(
            enabled: true,
            state: .armed,
            pressure: nil,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertFalse(armed.send)
        XCTAssertEqual(armed.state.phase, .armed)

        let streak = fired(clearSince: Date(timeIntervalSince1970: 1_700_000_100))
        let skipped = AlertRule.memoryPressure.advance(
            enabled: true,
            state: streak,
            pressure: nil,
            at: Date(timeIntervalSince1970: 1_700_000_400)
        )
        XCTAssertFalse(skipped.send)
        XCTAssertEqual(skipped.state, streak)

        let rearmed = AlertRule.memoryPressure.advance(
            enabled: true,
            state: skipped.state,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_400)
        )
        XCTAssertFalse(rearmed.send)
        XCTAssertEqual(rearmed.state.phase, .armed)
    }

    func testShortNormalGapAfterElevatedDoesNotRearm() {
        let broken = AlertRule.memoryPressure.advance(
            enabled: true,
            state: fired(clearSince: Date(timeIntervalSince1970: 1_700_000_100)),
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let restarted = AlertRule.memoryPressure.advance(
            enabled: true,
            state: broken.state,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_210)
        )
        XCTAssertFalse(restarted.send)
        XCTAssertEqual(restarted.state.phase, .fired(clearSince: Date(timeIntervalSince1970: 1_700_000_210)))

        let stillFired = AlertRule.memoryPressure.advance(
            enabled: true,
            state: restarted.state,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_509)
        )
        XCTAssertFalse(stillFired.send)
        XCTAssertEqual(stillFired.state.phase, .fired(clearSince: Date(timeIntervalSince1970: 1_700_000_210)))
    }

    func testNormalWhileArmedDoesNotSend() {
        let decision = AlertRule.memoryPressure.advance(
            enabled: true,
            state: .armed,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertFalse(decision.send)
        XCTAssertEqual(decision.state.phase, .armed)
    }

    func testSwitchOffDoesNotSendOrAdvance() {
        let armed = AlertRule.memoryPressure.advance(
            enabled: false,
            state: .armed,
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertFalse(armed.send)
        XCTAssertEqual(armed.state.phase, .armed)

        let streak = fired(clearSince: Date(timeIntervalSince1970: 1_700_000_100))
        let held = AlertRule.memoryPressure.advance(
            enabled: false,
            state: streak,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_400)
        )
        XCTAssertFalse(held.send)
        XCTAssertEqual(held.state, streak)
    }

    func testCopyNamesTheHeaviestAppAndStaysCalm() {
        XCTAssertEqual(
            PressureNoticeCopy.body(heaviestAppName: nil),
            "内存压力偏高，可以看看谁占得最多"
        )
        XCTAssertEqual(
            PressureNoticeCopy.body(heaviestAppName: "   "),
            "内存压力偏高，可以看看谁占得最多"
        )
        XCTAssertEqual(
            PressureNoticeCopy.body(heaviestAppName: "Safari"),
            "内存压力偏高，可以看看谁占得最多：Safari"
        )
        XCTAssertEqual(PressureNoticeCopy.permissionDenied, "系统通知未授权")
        let named = PressureNoticeCopy.body(heaviestAppName: "Safari")
        for word in ["危险", "危急", "泄漏", "泄露", "告警"] {
            XCTAssertFalse(named.contains(word), word)
            XCTAssertFalse(PressureNoticeCopy.permissionDenied.contains(word), word)
        }
    }

    func testFailedOrUnacceptedFrameDropsRetainedPressure() {
        XCTAssertNil(
            PressureNoticeReading.pressure(
                accepted: false,
                samplingFailed: true,
                snapshotPressure: .elevated
            )
        )
        XCTAssertNil(
            PressureNoticeReading.pressure(
                accepted: false,
                samplingFailed: false,
                snapshotPressure: .elevated
            )
        )
        XCTAssertNil(
            PressureNoticeReading.pressure(
                accepted: true,
                samplingFailed: true,
                snapshotPressure: .normal
            )
        )
        XCTAssertEqual(
            PressureNoticeReading.pressure(
                accepted: true,
                samplingFailed: false,
                snapshotPressure: .elevated
            ),
            .elevated
        )
        XCTAssertEqual(
            PressureNoticeReading.pressure(
                accepted: true,
                samplingFailed: false,
                snapshotPressure: .normal
            ),
            .normal
        )
    }

    func testAbsentPreferenceStaysOn() {
        let suite = "pulse.pressureNotice.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertEqual(PressureNoticePreference.defaultsKey, "pulse.pressureNotice")
        XCTAssertTrue(PressureNoticePreference.isEnabled(in: defaults))
        defaults.set(false, forKey: PressureNoticePreference.defaultsKey)
        XCTAssertFalse(PressureNoticePreference.isEnabled(in: defaults))
        defaults.set(true, forKey: PressureNoticePreference.defaultsKey)
        XCTAssertTrue(PressureNoticePreference.isEnabled(in: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    private func fired(clearSince: Date?) -> AlertRule.State {
        AlertRule.State(phase: .fired(clearSince: clearSince))
    }
}
