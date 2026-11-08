import XCTest
@testable import SamplingCore

final class ProcessPermissionFootnoteTests: XCTestCase {
    func testZeroAndNegativeCountsHaveNoSentence() {
        XCTAssertNil(ProcessPermissionFootnote.sentence(deniedCount: 0))
        XCTAssertNil(ProcessPermissionFootnote.sentence(deniedCount: -1))
    }

    func testPositiveCountIsTheExactPermissionSentence() {
        XCTAssertEqual(
            ProcessPermissionFootnote.sentence(deniedCount: 1),
            "另有 1 个系统进程没有读取权限"
        )
        XCTAssertEqual(
            ProcessPermissionFootnote.sentence(deniedCount: 228),
            "另有 228 个系统进程没有读取权限"
        )
    }

    func testEPERMCountsAndESRCHDoesNot() {
        XCTAssertTrue(ProcessPermissionFootnote.countsTaskInfoFailure(errno: 1))
        XCTAssertFalse(ProcessPermissionFootnote.countsTaskInfoFailure(errno: 3))
        XCTAssertFalse(ProcessPermissionFootnote.countsTaskInfoFailure(errno: 0))
        XCTAssertFalse(ProcessPermissionFootnote.countsTaskInfoFailure(errno: 5))
        XCTAssertEqual(
            ProcessPermissionFootnote.deniedCount(taskInfoErrnos: [1, 3, 1, 0, 5]),
            2
        )
        XCTAssertEqual(ProcessPermissionFootnote.deniedCount(taskInfoErrnos: [1]), 1)
        XCTAssertEqual(ProcessPermissionFootnote.deniedCount(taskInfoErrnos: [1]), 1)
        XCTAssertEqual(ProcessPermissionFootnote.deniedCount(taskInfoErrnos: []), 0)
        XCTAssertEqual(ProcessPermissionFootnote.deniedCount(taskInfoErrnos: [3, 3]), 0)
    }

    func testFailedListPublishesNoSentenceAndNoZero() {
        XCTAssertNil(ProcessPermissionFootnote.published(deniedCount: 4, processListFailed: true))
        XCTAssertNil(ProcessPermissionFootnote.published(deniedCount: 0, processListFailed: true))
        XCTAssertNil(ProcessPermissionFootnote.published(deniedCount: -3, processListFailed: false))
        XCTAssertNil(ProcessPermissionFootnote.published(deniedCount: 0, processListFailed: false))
        XCTAssertEqual(
            ProcessPermissionFootnote.published(deniedCount: 4, processListFailed: false),
            "另有 4 个系统进程没有读取权限"
        )
        XCTAssertNotEqual(
            ProcessPermissionFootnote.published(deniedCount: 0, processListFailed: true) ?? "",
            "0"
        )
    }

    func testTableHidesTheFootnoteWhenTheListFailedOrTheTableIsAbsent() {
        let sentence = "另有 4 个系统进程没有读取权限"
        XCTAssertNil(
            ProcessPermissionFootnote.visibleSentence(
                sentence,
                processListFailed: true,
                showsProcessTable: true
            )
        )
        XCTAssertNil(
            ProcessPermissionFootnote.visibleSentence(
                sentence,
                processListFailed: false,
                showsProcessTable: false
            )
        )
        XCTAssertNil(
            ProcessPermissionFootnote.visibleSentence(
                nil,
                processListFailed: false,
                showsProcessTable: true
            )
        )
        XCTAssertNil(
            ProcessPermissionFootnote.visibleSentence(
                "",
                processListFailed: false,
                showsProcessTable: true
            )
        )
        XCTAssertNil(
            ProcessPermissionFootnote.visibleSentence(
                "0",
                processListFailed: true,
                showsProcessTable: true
            )
        )
        XCTAssertNil(
            ProcessPermissionFootnote.visibleSentence(
                "0",
                processListFailed: false,
                showsProcessTable: true
            )
        )
        XCTAssertEqual(
            ProcessPermissionFootnote.visibleSentence(
                sentence,
                processListFailed: false,
                showsProcessTable: true
            ),
            sentence
        )
    }
}
