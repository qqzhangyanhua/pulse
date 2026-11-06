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

    func testPrimaryClickShowsPopoverAndSecondaryClickIsQuit() {
        XCTAssertEqual(
            MenuBarPointer.classify(isSecondaryClick: false, controlDown: false),
            .primary
        )
        XCTAssertEqual(MenuBarPointer.primary.statusItemAction, .showPopover)
        XCTAssertTrue(MenuBarPointer.primary.showsPopover)
        XCTAssertFalse(MenuBarPointer.primary.showsQuitMenu)
        XCTAssertEqual(
            MenuBarPointer.classify(isSecondaryClick: true, controlDown: false).statusItemAction,
            .showQuitMenu
        )
        XCTAssertTrue(MenuBarPointer.classify(isSecondaryClick: true, controlDown: false).showsQuitMenu)
        XCTAssertTrue(MenuBarPointer.classify(isSecondaryClick: false, controlDown: true).showsQuitMenu)
        XCTAssertFalse(MenuBarPointer.secondary.showsPopover)
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

    func testPopoverShellIsSingleColumnPressureTop3AndOpenPulse() {
        XCTAssertEqual(
            MenuBarPopoverShell.sections,
            [.hostPressure, .topProcesses, .openPulse]
        )
        XCTAssertEqual(
            MenuBarPopoverSection.allCases.map(\.rawValue),
            ["hostPressure", "topProcesses", "openPulse"]
        )
        XCTAssertFalse(MenuBarPopoverSection.allCases.map(\.rawValue).contains("usedMemory"))
        XCTAssertEqual(MenuBarPopoverShell.hostBlockLineCount, 2)
        XCTAssertEqual(MenuBarPopoverShell.maxProcessRows, 3)
        XCTAssertEqual(
            MenuBarPopoverShell.placeholder(for: .hostPressure),
            MenuBarCopy.unavailableTooltip
        )
        XCTAssertEqual(
            MenuBarPopoverShell.placeholder(for: .topProcesses),
            MenuBarCopy.processesEmpty
        )
        XCTAssertEqual(
            MenuBarPopoverShell.placeholder(for: .openPulse),
            MenuBarCopy.openPulseTitle
        )
        XCTAssertEqual(MenuBarCopy.openPulseTitle, "打开 Pulse")
        XCTAssertEqual(MenuBarCopy.processesEmpty, "暂无进程")
        XCTAssertEqual(MenuBarCopy.unavailableTooltip, "暂时读不到")
    }

    func testPopoverShellReusesTwoLevelPressureCopyAndNeverScares() {
        XCTAssertEqual(PressureLevel.normal.title, "正常")
        XCTAssertEqual(PressureLevel.normal.caption, "余量充足")
        XCTAssertEqual(PressureLevel.elevated.title, "偏高")
        XCTAssertEqual(PressureLevel.elevated.caption, "余量紧张")

        let blob = [
            PressureLevel.normal.title,
            PressureLevel.normal.caption,
            PressureLevel.elevated.title,
            PressureLevel.elevated.caption,
            MenuBarPopoverShell.placeholder(for: .hostPressure),
            MenuBarPopoverShell.placeholder(for: .topProcesses),
            MenuBarPopoverShell.placeholder(for: .openPulse),
            MenuBarCopy.quitTitle,
        ].joined(separator: "\n")
        for word in ["危急", "泄漏", "泄露", "危险", "告警"] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("leak"))
        XCTAssertFalse(MenuBarPopoverShell.placeholder(for: .hostPressure).contains("正常"))
        XCTAssertFalse(MenuBarPopoverShell.placeholder(for: .topProcesses).contains("0"))
        XCTAssertFalse(MenuBarCopy.openPulseTitle.contains("结束"))
        XCTAssertFalse(MenuBarCopy.openPulseTitle.contains("立即处理"))
    }

    func testTopProcessesNoteIsStaticCopyAndNotASecondLiteralInTheView() throws {
        let sentence = "按内存页表头、完整列表前 3，不含当前过滤。"
        XCTAssertEqual(MenuBarCopy.topProcessesNote, sentence)
        XCTAssertFalse(sentence.contains("过滤后前三"))

        let model = try repoText("Pulse/MenuBar/MenuBarStatus.swift")
        XCTAssertEqual(occurrenceCount(of: sentence, in: model), 1)
        let project = try slice(from: "static func project(", until: "static func topProcesses(", in: model)
        XCTAssertFalse(project.contains("topProcessesNote"))
        XCTAssertFalse(project.contains(sentence))
        XCTAssertFalse(project.contains("visibleRows"))
        XCTAssertFalse(project.contains("risingOnlyFilter"))

        let view = try repoText("Pulse/MenuBar/MenuBarPopoverView.swift")
        XCTAssertEqual(occurrenceCount(of: "MenuBarCopy.topProcessesNote", in: view), 1)
        XCTAssertFalse(view.contains(sentence))
        XCTAssertFalse(view.contains("过滤后前三"))
        XCTAssertFalse(view.contains("filter"))
        XCTAssertFalse(view.contains("visibleRows"))
        XCTAssertFalse(view.contains("risingOnlyFilter"))
        XCTAssertTrue(view.contains(".frame(width: 248, alignment: .topLeading)"))
        XCTAssertTrue(view.contains("strip.processesEmptyCopy"))
        let noteAt = try index(of: "MenuBarCopy.topProcessesNote", in: view)
        let emptyAt = try index(of: "strip.processesEmptyCopy", in: view)
        XCTAssertLessThan(noteAt, emptyAt)
    }

    private func repoText(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func index(of needle: String, in haystack: String) throws -> Int {
        guard let range = haystack.range(of: needle) else {
            XCTFail("missing \(needle)")
            return 0
        }
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    private func slice(from start: String, until end: String, in source: String) throws -> String {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            XCTFail("missing slice \(start)")
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}
