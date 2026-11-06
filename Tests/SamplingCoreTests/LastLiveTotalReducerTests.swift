import XCTest
@testable import SamplingCore

/// Phase 18 last-live denominator and subject reset.
///
/// Linux SamplingCore only. These cases step the reducer. They do not project
/// a page, and a pass is not a SwiftUI sidebar or a Mac click.
final class LastLiveTotalReducerTests: XCTestCase {
    private let gib: UInt64 = 1_073_741_824
    private let pidA: Int32 = 4
    private let pidB: Int32 = 9

    func testSameBeatSelectedPidNilFreezesEightOfSixteenNotEighteen() {
        let eight = 8 * gib
        let sixteen = 16 * gib
        let eighteen = 18 * gib
        let live = LastLiveTotalReducer.step(.empty, .live(pid: pidA, totalBytes: sixteen))
        let previous = beat(
            subject: pidA,
            absent: false,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: pidA,
            listSelected: pidA
        )
        let current = beat(
            subject: pidA,
            absent: true,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: nil,
            listSelected: nil
        )
        let sidebarEvents = LastLiveTotalReducer.eventsForSidebar(
            previous: previous,
            current: current,
            snapshotTotalBytes: eighteen
        )
        XCTAssertEqual(sidebarEvents, [.freeze(pid: pidA, memoryBytes: eight)])
        XCTAssertFalse(sidebarEvents.contains(.subject(nil)))

        let frozenState = apply(live, sidebarEvents)
        XCTAssertEqual(frozenState.frozen?.pid, pidA)
        XCTAssertEqual(frozenState.frozen?.memoryBytes, eight)
        XCTAssertEqual(frozenState.frozen?.physicalTotalBytes, sixteen)
        XCTAssertEqual(frozenState.lastLive?.totalBytes, sixteen)
        XCTAssertNotEqual(frozenState.frozen?.physicalTotalBytes, eighteen)

        let beforeCallback = LastLiveTotalReducer.frozenSemanticsForProjection(
            showsAbsentRecord: true,
            state: live,
            detailPid: pidA,
            detailMemoryBytes: eight
        )
        XCTAssertEqual(beforeCallback?.physicalTotalBytes, sixteen)
        XCTAssertEqual(beforeCallback?.memoryBytes, eight)
        XCTAssertNil(
            LastLiveTotalReducer.frozenSemanticsForProjection(
                showsAbsentRecord: false,
                state: frozenState,
                detailPid: pidA,
                detailMemoryBytes: eight
            )
        )
    }

    func testSnapshotAndSidebarCallbackOrderBothRefuseLiveEighteen() {
        let eight = 8 * gib
        let sixteen = 16 * gib
        let eighteen = 18 * gib
        let live = LastLiveTotalReducer.step(.empty, .live(pid: pidA, totalBytes: sixteen))
        let previous = beat(
            subject: pidA,
            absent: false,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: pidA,
            listSelected: pidA
        )
        let current = beat(
            subject: pidA,
            absent: true,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: nil,
            listSelected: nil
        )
        let gate = SidebarLiveGate(beat: current, snapshotTotalBytes: eighteen)
        let snapshotEvent = LastLiveTotalReducer.eventForCurrentSidebar(gate)
        XCTAssertNil(snapshotEvent)
        let sidebarEvents = LastLiveTotalReducer.eventsForSidebar(
            previous: previous,
            current: current,
            snapshotTotalBytes: eighteen
        )
        let snapshotFirst = apply(live, [snapshotEvent].compactMap { $0 } + sidebarEvents)
        let freezeFirst = apply(live, sidebarEvents + [snapshotEvent].compactMap { $0 })
        for state in [snapshotFirst, freezeFirst] {
            XCTAssertEqual(state.frozen?.physicalTotalBytes, sixteen)
            XCTAssertEqual(state.frozen?.memoryBytes, eight)
        }
        let afterFreeze = apply(live, sidebarEvents)
        let ignored = LastLiveTotalReducer.step(afterFreeze, .live(pid: pidA, totalBytes: eighteen))
        XCTAssertEqual(ignored.frozen?.physicalTotalBytes, sixteen)
        XCTAssertEqual(ignored.lastLive?.totalBytes, sixteen)

        let adopted = LastLiveTotalReducer.step(
            LastLiveTotalReducer.step(live, .live(pid: pidA, totalBytes: eighteen)),
            .freeze(pid: pidA, memoryBytes: eight)
        )
        XCTAssertEqual(adopted.frozen?.physicalTotalBytes, eighteen)
        XCTAssertNil(snapshotEvent)

        let stillMatchingLivePid = beat(
            subject: pidA,
            absent: true,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: pidA,
            listSelected: nil
        )
        XCTAssertFalse(stillMatchingLivePid.isNormalLive)
        XCTAssertNil(
            LastLiveTotalReducer.eventForCurrentSidebar(
                SidebarLiveGate(beat: stillMatchingLivePid, snapshotTotalBytes: eighteen)
            )
        )
    }

    func testSubjectDismissAndNewLiveClearThePreviousDenominator() {
        let sixteen = 16 * gib
        let eight = 8 * gib
        let frozen = LastLiveTotalReducer.step(
            LastLiveTotalReducer.step(.empty, .live(pid: pidA, totalBytes: sixteen)),
            .freeze(pid: pidA, memoryBytes: eight)
        )
        let absentA = beat(
            subject: pidA,
            absent: true,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: nil,
            listSelected: nil,
            seriesEmpty: true
        )
        let liveB = beat(
            subject: pidB,
            absent: false,
            detailPid: pidB,
            memory: 1,
            hasDetail: true,
            livePid: pidB,
            listSelected: pidB
        )
        let placeholderB = beat(
            subject: pidB,
            absent: false,
            detailPid: pidB,
            memory: 1,
            hasDetail: true,
            livePid: nil,
            listSelected: pidB,
            seriesEmpty: true
        )
        XCTAssertTrue(placeholderB.isRowPlaceholder)
        XCTAssertFalse(placeholderB.isNormalLive)
        XCTAssertEqual(
            LastLiveTotalReducer.eventsForSidebar(previous: absentA, current: liveB, snapshotTotalBytes: 4 * gib),
            [.subject(pidB), .live(pid: pidB, totalBytes: 4 * gib)]
        )
        XCTAssertEqual(
            LastLiveTotalReducer.eventsForSidebar(previous: absentA, current: placeholderB, snapshotTotalBytes: sixteen),
            [.subject(pidB)]
        )
        let moved = apply(
            frozen,
            LastLiveTotalReducer.eventsForSidebar(previous: absentA, current: placeholderB, snapshotTotalBytes: sixteen)
        )
        XCTAssertNil(moved.lastLive)
        XCTAssertNil(moved.frozen)
        let followed = LastLiveTotalReducer.step(moved, .live(pid: pidB, totalBytes: nil))
        XCTAssertNil(followed.lastLive)
        let bLive = LastLiveTotalReducer.step(moved, .live(pid: pidB, totalBytes: 9 * gib))
        XCTAssertEqual(bLive.lastLive, LastLiveTotal(pid: pidB, totalBytes: 9 * gib))
        XCTAssertNotEqual(bLive.lastLive?.totalBytes, sixteen)

        let dismissed = LastLiveTotalReducer.step(frozen, .subject(nil))
        XCTAssertEqual(dismissed, .empty)
        let dismissEvents = LastLiveTotalReducer.eventsForSidebar(
            previous: liveB,
            current: beat(subject: nil, absent: false),
            snapshotTotalBytes: sixteen
        )
        XCTAssertEqual(dismissEvents, [.subject(nil)])
        XCTAssertEqual(apply(bLive, dismissEvents), .empty)

        let rebirthNil = LastLiveTotalReducer.eventsForSidebar(
            previous: absentA,
            current: beat(
                subject: pidA,
                absent: false,
                detailPid: pidA,
                memory: 3,
                hasDetail: true,
                livePid: pidA,
                listSelected: pidA,
                seriesEmpty: true
            ),
            snapshotTotalBytes: nil
        )
        XCTAssertEqual(rebirthNil, [.newLiveSubject(pid: pidA, totalBytes: nil)])
        let cleared = apply(frozen, rebirthNil)
        XCTAssertNil(cleared.lastLive)
        XCTAssertNil(cleared.frozen)
        let rebirthEighteen = LastLiveTotalReducer.eventsForSidebar(
            previous: absentA,
            current: beat(
                subject: pidA,
                absent: false,
                detailPid: pidA,
                memory: 3,
                hasDetail: true,
                livePid: pidA,
                listSelected: pidA
            ),
            snapshotTotalBytes: 18 * gib
        )
        XCTAssertEqual(rebirthEighteen, [.newLiveSubject(pid: pidA, totalBytes: 18 * gib)])
        let restarted = apply(frozen, rebirthEighteen)
        XCTAssertEqual(restarted.lastLive?.totalBytes, 18 * gib)
        XCTAssertNil(restarted.frozen)
        XCTAssertNotEqual(restarted.lastLive?.totalBytes, sixteen)
    }

    func testLiveNilAndZeroDoNotOverwriteTheRememberedTotal() {
        var state = LastLiveTotalReducer.step(.empty, .live(pid: pidA, totalBytes: 16 * gib))
        state = LastLiveTotalReducer.step(state, .live(pid: pidA, totalBytes: nil))
        state = LastLiveTotalReducer.step(state, .live(pid: pidA, totalBytes: 0))
        XCTAssertEqual(state.lastLive?.totalBytes, 16 * gib)
        XCTAssertNil(state.frozen)
        XCTAssertNil(
            LastLiveTotalReducer.frozenSemanticsForProjection(
                showsAbsentRecord: false,
                state: state,
                detailPid: pidA,
                detailMemoryBytes: 8 * gib
            )
        )
    }

    func testNeverValidLiveTotalStaysNilWhenALaterEighteenArrives() {
        var state = LastLiveTotalReducer.step(.empty, .live(pid: pidA, totalBytes: nil))
        state = LastLiveTotalReducer.step(state, .live(pid: pidA, totalBytes: 0))
        XCTAssertNil(state.lastLive)
        state = LastLiveTotalReducer.step(state, .freeze(pid: pidA, memoryBytes: 8 * gib))
        XCTAssertNil(state.frozen?.physicalTotalBytes)
        state = LastLiveTotalReducer.step(state, .live(pid: pidA, totalBytes: 18 * gib))
        XCTAssertNil(state.frozen?.physicalTotalBytes)
        XCTAssertNil(state.lastLive)
        XCTAssertNotEqual(state.frozen?.physicalTotalBytes, 18 * gib)
    }

    func testLivePidMismatchIsIgnoredAndFreezeDoesNotBorrowAnotherPid() {
        var state = LastLiveTotalReducer.step(.empty, .live(pid: pidA, totalBytes: 16 * gib))
        state = LastLiveTotalReducer.step(state, .live(pid: pidB, totalBytes: 32 * gib))
        XCTAssertEqual(state.lastLive, LastLiveTotal(pid: pidA, totalBytes: 16 * gib))
        XCTAssertNil(state.frozen)
        state = LastLiveTotalReducer.step(state, .freeze(pid: pidB, memoryBytes: 8 * gib))
        XCTAssertEqual(state.frozen?.pid, pidB)
        XCTAssertNil(state.frozen?.physicalTotalBytes)
        XCTAssertEqual(state.lastLive?.pid, pidA)
        XCTAssertEqual(state.lastLive?.totalBytes, 16 * gib)
    }

    func testPlaceholderIsNotLiveAndListSelectionNilDoesNotClearTheCache() {
        let placeholder = beat(
            subject: pidA,
            absent: false,
            detailPid: pidA,
            memory: 100,
            hasDetail: true,
            livePid: nil,
            listSelected: pidA,
            seriesEmpty: true
        )
        XCTAssertTrue(placeholder.isRowPlaceholder)
        XCTAssertFalse(placeholder.isNormalLive)
        XCTAssertNil(
            LastLiveTotalReducer.eventForCurrentSidebar(
                SidebarLiveGate(beat: placeholder, snapshotTotalBytes: 18 * gib)
            )
        )
        XCTAssertNil(
            LastLiveTotalReducer.eventForCurrentSidebar(
                SidebarLiveGate(beat: beat(subject: nil, absent: false), snapshotTotalBytes: 16 * gib)
            )
        )

        let previous = beat(
            subject: pidA,
            absent: false,
            detailPid: pidA,
            memory: 8 * gib,
            hasDetail: true,
            livePid: pidA,
            listSelected: pidA
        )
        let clearedList = beat(
            subject: pidA,
            absent: false,
            detailPid: pidA,
            memory: 8 * gib,
            hasDetail: true,
            livePid: nil,
            listSelected: nil,
            seriesEmpty: true
        )
        XCTAssertTrue(clearedList.isRowPlaceholder)
        XCTAssertEqual(
            LastLiveTotalReducer.eventsForSidebar(
                previous: previous,
                current: clearedList,
                snapshotTotalBytes: 18 * gib
            ),
            []
        )
        let state = apply(
            LastLiveTotalReducer.step(.empty, .live(pid: pidA, totalBytes: 16 * gib)),
            []
        )
        XCTAssertEqual(state.lastLive?.totalBytes, 16 * gib)
        XCTAssertNil(state.frozen)

        let onlyListChanges = beat(
            subject: pidA,
            absent: false,
            detailPid: pidA,
            memory: 8 * gib,
            hasDetail: true,
            livePid: pidA,
            listSelected: nil
        )
        XCTAssertEqual(
            LastLiveTotalReducer.eventsForSidebar(
                previous: previous,
                current: onlyListChanges,
                snapshotTotalBytes: 18 * gib
            ),
            []
        )
        XCTAssertEqual(
            LastLiveTotalReducer.eventForCurrentSidebar(
                SidebarLiveGate(beat: previous, snapshotTotalBytes: 16 * gib)
            ),
            LastLiveTotalReducer.eventForCurrentSidebar(
                SidebarLiveGate(beat: onlyListChanges, snapshotTotalBytes: 16 * gib)
            )
        )

        let noCard = beat(subject: pidA, absent: true, listSelected: nil)
        XCTAssertEqual(
            LastLiveTotalReducer.eventsForSidebar(
                previous: previous,
                current: noCard,
                snapshotTotalBytes: 18 * gib
            ),
            []
        )
    }

    func testEmptySeriesRowPlaceholderBecomingRealDetailObservesTheTotal() {
        let eight = 8 * gib
        let sixteen = 16 * gib
        let eighteen = 18 * gib
        let placeholder = beat(
            subject: pidA,
            absent: false,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: nil,
            listSelected: pidA,
            seriesEmpty: true
        )
        XCTAssertTrue(placeholder.isRowPlaceholder)
        XCTAssertFalse(SidebarLiveGate(beat: placeholder, snapshotTotalBytes: sixteen).isNormalLive)
        XCTAssertNil(
            LastLiveTotalReducer.eventForCurrentSidebar(
                SidebarLiveGate(beat: placeholder, snapshotTotalBytes: sixteen)
            )
        )

        let realStillEmpty = beat(
            subject: pidA,
            absent: false,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: pidA,
            listSelected: pidA,
            seriesEmpty: true
        )
        XCTAssertFalse(realStillEmpty.isRowPlaceholder)
        XCTAssertTrue(realStillEmpty.isNormalLive)
        let observed = LastLiveTotalReducer.eventsForSidebar(
            previous: placeholder,
            current: realStillEmpty,
            snapshotTotalBytes: sixteen
        )
        XCTAssertEqual(observed, [.live(pid: pidA, totalBytes: sixteen)])
        let state = apply(.empty, observed)
        XCTAssertEqual(state.lastLive, LastLiveTotal(pid: pidA, totalBytes: sixteen))
        XCTAssertNil(state.frozen)

        let missed = apply(.empty, [])
        let absent = beat(
            subject: pidA,
            absent: true,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: nil,
            listSelected: nil,
            seriesEmpty: true
        )
        let freeze = LastLiveTotalReducer.eventsForSidebar(
            previous: realStillEmpty,
            current: absent,
            snapshotTotalBytes: eighteen
        )
        XCTAssertEqual(freeze, [.freeze(pid: pidA, memoryBytes: eight)])
        XCTAssertNil(apply(missed, freeze).frozen?.physicalTotalBytes)
        let kept = apply(state, freeze)
        XCTAssertEqual(kept.frozen?.memoryBytes, eight)
        XCTAssertEqual(kept.frozen?.physicalTotalBytes, sixteen)
        XCTAssertNotEqual(kept.frozen?.physicalTotalBytes, eighteen)

        XCTAssertEqual(
            LastLiveTotalReducer.eventsForSidebar(
                previous: realStillEmpty,
                current: realStillEmpty,
                snapshotTotalBytes: eighteen
            ),
            []
        )
        let straightToAbsent = LastLiveTotalReducer.eventsForSidebar(
            previous: placeholder,
            current: absent,
            snapshotTotalBytes: eighteen
        )
        XCTAssertEqual(straightToAbsent, [.freeze(pid: pidA, memoryBytes: eight)])
        XCTAssertFalse(straightToAbsent.contains(.live(pid: pidA, totalBytes: eighteen)))

        let absentWithMatchingPid = beat(
            subject: pidA,
            absent: true,
            detailPid: pidA,
            memory: eight,
            hasDetail: true,
            livePid: pidA,
            listSelected: nil
        )
        XCTAssertEqual(
            LastLiveTotalReducer.eventsForSidebar(
                previous: absent,
                current: absentWithMatchingPid,
                snapshotTotalBytes: eighteen
            ),
            []
        )
        XCTAssertNil(
            LastLiveTotalReducer.eventForCurrentSidebar(
                SidebarLiveGate(beat: absentWithMatchingPid, snapshotTotalBytes: eighteen)
            )
        )
    }

    func testLastPositiveUpdatesUntilFreezeAndASecondFreezeDoesNotRelock() {
        var state = LastLiveTotalReducer.step(.empty, .live(pid: pidA, totalBytes: 16 * gib))
        state = LastLiveTotalReducer.step(state, .live(pid: pidA, totalBytes: 32 * gib))
        state = LastLiveTotalReducer.step(state, .live(pid: pidA, totalBytes: 0))
        XCTAssertEqual(state.lastLive?.totalBytes, 32 * gib)
        state = LastLiveTotalReducer.step(state, .freeze(pid: pidA, memoryBytes: 8 * gib))
        XCTAssertEqual(state.frozen?.physicalTotalBytes, 32 * gib)
        XCTAssertEqual(state.frozen?.memoryBytes, 8 * gib)
        state = LastLiveTotalReducer.step(state, .freeze(pid: pidA, memoryBytes: 99))
        XCTAssertEqual(state.frozen?.memoryBytes, 8 * gib)
        XCTAssertEqual(state.frozen?.physicalTotalBytes, 32 * gib)
        XCTAssertNotEqual(state.frozen?.physicalTotalBytes, 18 * gib)
    }

    private func apply(_ state: LastLiveTotalState, _ events: [LastLiveTotalEvent]) -> LastLiveTotalState {
        events.reduce(state) { LastLiveTotalReducer.step($0, $1) }
    }

    private func beat(
        subject: Int32?,
        absent: Bool,
        detailPid: Int32? = nil,
        memory: UInt64? = nil,
        hasDetail: Bool = false,
        livePid: Int32? = nil,
        listSelected: Int32? = nil,
        seriesEmpty: Bool = false
    ) -> SidebarSubjectBeat {
        SidebarSubjectBeat(
            subjectPid: subject,
            showsAbsentRecord: absent,
            sidebarDetailPid: detailPid,
            sidebarDetailMemoryBytes: memory,
            hasSidebarDetail: hasDetail,
            liveDetailPid: livePid,
            listSelectedPid: listSelected,
            sidebarSeriesEmpty: seriesEmpty
        )
    }
}
