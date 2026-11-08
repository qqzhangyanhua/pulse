import XCTest
@testable import SamplingCore

final class PressureNoticeTests: XCTestCase {
    func testFirstElevatedFrameWhileArmedSendsAndFires() {
        let decision = PressureNotice.advance(
            enabled: true,
            phase: .armed,
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(decision.send)
        XCTAssertEqual(decision.phase, .fired(normalSince: nil))
    }

    func testElevatedWhileFiredDoesNotSendAndClearsTheNormalStreak() {
        let streak = Date(timeIntervalSince1970: 1_700_000_100)
        let decision = PressureNotice.advance(
            enabled: true,
            phase: .fired(normalSince: streak),
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_120)
        )
        XCTAssertFalse(decision.send)
        XCTAssertEqual(decision.phase, .fired(normalSince: nil))
    }

    func testFiveMinutesOfContinuousNormalRearmsAndAShorterGapDoesNot() {
        let fired = PressureNotice.advance(
            enabled: true,
            phase: .armed,
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let started = PressureNotice.advance(
            enabled: true,
            phase: fired.phase,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_100)
        )
        XCTAssertFalse(started.send)
        XCTAssertEqual(started.phase, .fired(normalSince: Date(timeIntervalSince1970: 1_700_000_100)))

        let short = PressureNotice.advance(
            enabled: true,
            phase: started.phase,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_399)
        )
        XCTAssertFalse(short.send)
        XCTAssertEqual(short.phase, .fired(normalSince: Date(timeIntervalSince1970: 1_700_000_100)))

        let rearmed = PressureNotice.advance(
            enabled: true,
            phase: short.phase,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_400)
        )
        XCTAssertFalse(rearmed.send)
        XCTAssertEqual(rearmed.phase, .armed)

        let again = PressureNotice.advance(
            enabled: true,
            phase: rearmed.phase,
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_401)
        )
        XCTAssertTrue(again.send)
        XCTAssertEqual(again.phase, .fired(normalSince: nil))
    }

    func testNilFrameDoesNotSendOrResetPhase() {
        let armed = PressureNotice.advance(
            enabled: true,
            phase: .armed,
            pressure: nil,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertFalse(armed.send)
        XCTAssertEqual(armed.phase, .armed)

        let streak = PressureNoticePhase.fired(normalSince: Date(timeIntervalSince1970: 1_700_000_100))
        let skipped = PressureNotice.advance(
            enabled: true,
            phase: streak,
            pressure: nil,
            at: Date(timeIntervalSince1970: 1_700_000_400)
        )
        XCTAssertFalse(skipped.send)
        XCTAssertEqual(skipped.phase, streak)

        let rearmed = PressureNotice.advance(
            enabled: true,
            phase: skipped.phase,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_400)
        )
        XCTAssertFalse(rearmed.send)
        XCTAssertEqual(rearmed.phase, .armed)
    }

    func testShortNormalGapAfterElevatedDoesNotRearm() {
        let broken = PressureNotice.advance(
            enabled: true,
            phase: .fired(normalSince: Date(timeIntervalSince1970: 1_700_000_100)),
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let restarted = PressureNotice.advance(
            enabled: true,
            phase: broken.phase,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_210)
        )
        XCTAssertFalse(restarted.send)
        XCTAssertEqual(restarted.phase, .fired(normalSince: Date(timeIntervalSince1970: 1_700_000_210)))

        let stillFired = PressureNotice.advance(
            enabled: true,
            phase: restarted.phase,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_509)
        )
        XCTAssertFalse(stillFired.send)
        XCTAssertEqual(stillFired.phase, .fired(normalSince: Date(timeIntervalSince1970: 1_700_000_210)))
    }

    func testNormalWhileArmedDoesNotSend() {
        let decision = PressureNotice.advance(
            enabled: true,
            phase: .armed,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertFalse(decision.send)
        XCTAssertEqual(decision.phase, .armed)
    }

    func testSwitchOffDoesNotSendOrAdvance() {
        let armed = PressureNotice.advance(
            enabled: false,
            phase: .armed,
            pressure: .elevated,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertFalse(armed.send)
        XCTAssertEqual(armed.phase, .armed)

        let streak = PressureNoticePhase.fired(normalSince: Date(timeIntervalSince1970: 1_700_000_100))
        let held = PressureNotice.advance(
            enabled: false,
            phase: streak,
            pressure: .normal,
            at: Date(timeIntervalSince1970: 1_700_000_400)
        )
        XCTAssertFalse(held.send)
        XCTAssertEqual(held.phase, streak)
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
}
