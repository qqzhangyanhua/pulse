import XCTest
@testable import SamplingCore

final class MenuBarStatusTests: XCTestCase {
    func testNormalPressureIsCalmGreenWithoutCopy() {
        let dot = MenuBarDot.resolve(pressure: .normal, samplingFailed: false)
        XCTAssertEqual(dot.kind, .calmGreen)
        XCTAssertEqual(dot.color, .calmGreen)
        XCTAssertNil(dot.tooltip)
        XCTAssertEqual(dot.statusItemTitle, "")
        XCTAssertFalse(dot.color.isAlarmRed)
    }

    func testElevatedPressureIsCalmAmberNotAlarmRed() {
        let dot = MenuBarDot.resolve(pressure: .elevated, samplingFailed: false)
        XCTAssertEqual(dot.kind, .calmAmber)
        XCTAssertEqual(dot.color, .calmAmber)
        XCTAssertNil(dot.tooltip)
        XCTAssertEqual(dot.statusItemTitle, "")
        XCTAssertFalse(dot.color.isAlarmRed)
        XCTAssertGreaterThan(dot.color.green, 0.40)
    }

    func testMissingSnapshotIsGrayAndSaysTemporarilyUnreadable() {
        let dot = MenuBarDot.resolve(pressure: nil, samplingFailed: false)
        XCTAssertEqual(dot, .unavailable)
        XCTAssertEqual(dot.kind, .unavailable)
        XCTAssertEqual(dot.tooltip, "暂时读不到")
        XCTAssertEqual(dot.statusItemTitle, "")
        XCTAssertFalse(dot.color.isAlarmRed)
    }

    func testSamplingFailureStaysGrayEvenIfAStalePressureIsStillAround() {
        let failedNormal = MenuBarDot.resolve(pressure: .normal, samplingFailed: true)
        let failedElevated = MenuBarDot.resolve(pressure: .elevated, samplingFailed: true)
        let failedEmpty = MenuBarDot.resolve(pressure: nil, samplingFailed: true)
        XCTAssertEqual(failedNormal, .unavailable)
        XCTAssertEqual(failedElevated, .unavailable)
        XCTAssertEqual(failedEmpty, .unavailable)
        XCTAssertEqual(failedElevated.tooltip, MenuBarCopy.unavailableTooltip)
    }

    func testBarCopyNeverCarriesPressureWordsOrMemoryFigures() {
        let dots = [
            MenuBarDot.resolve(pressure: .normal, samplingFailed: false),
            MenuBarDot.resolve(pressure: .elevated, samplingFailed: false),
            MenuBarDot.resolve(pressure: nil, samplingFailed: false),
            MenuBarDot.resolve(pressure: .elevated, samplingFailed: true),
        ]
        let banned = ["危险", "正常", "偏高", "GB", "MB", "%", "已用"]
        for dot in dots {
            let text = (dot.tooltip ?? "") + dot.statusItemTitle
            XCTAssertEqual(dot.statusItemTitle, "")
            for word in banned {
                XCTAssertFalse(text.contains(word), text)
            }
        }
        XCTAssertEqual(MenuBarCopy.quitTitle, "退出 Pulse")
        XCTAssertFalse(MenuBarCopy.quitTitle.contains("危险"))
    }

    func testPrimaryClickFocusesMemoryAndSecondaryClickIsQuit() {
        XCTAssertEqual(
            MenuBarPointer.classify(isSecondaryClick: false, controlDown: false),
            .primary
        )
        XCTAssertFalse(MenuBarPointer.primary.showsQuitMenu)
        XCTAssertTrue(MenuBarPointer.classify(isSecondaryClick: true, controlDown: false).showsQuitMenu)
        XCTAssertTrue(MenuBarPointer.classify(isSecondaryClick: false, controlDown: true).showsQuitMenu)
    }

    func testClickForcesMemoryPageFromAnyTab() {
        for page in DashboardPage.allCases {
            var navigation = MenuBarNavigation(selectedPage: page)
            navigation.focusMemoryPage()
            XCTAssertEqual(navigation.selectedPage, .memory)
        }
    }

    func testClosingTheWindowKeepsSamplingSlowerAndDoesNotTerminate() {
        XCTAssertFalse(MenuBarLifecycle.terminateAfterLastWindowClosed)

        let closed = MenuBarSamplingGate(sceneActive: true, mainWindowVisible: false)
        XCTAssertFalse(closed.isForeground)
        XCTAssertTrue(closed.step.samples)
        XCTAssertEqual(closed.step.sleepNanoseconds, SamplingPace.backgroundSleepNanoseconds)

        let backgroundApp = MenuBarSamplingGate(sceneActive: false, mainWindowVisible: true)
        XCTAssertFalse(backgroundApp.isForeground)
        XCTAssertTrue(backgroundApp.step.samples)
        XCTAssertEqual(backgroundApp.step.sleepNanoseconds, SamplingPace.backgroundSleepNanoseconds)

        let foreground = MenuBarSamplingGate(sceneActive: true, mainWindowVisible: true)
        XCTAssertTrue(foreground.isForeground)
        XCTAssertTrue(foreground.step.samples)
        XCTAssertEqual(foreground.step.sleepNanoseconds, SamplingPace.foregroundSleepNanoseconds)
    }
}
