import XCTest
@testable import SamplingCore

final class ProcessTreeTests: XCTestCase {
    func testEmptyInputHasNoRoots() {
        let tree = ProcessTree.build(from: [])

        XCTAssertEqual(tree.ancestors(of: 1), [])
        XCTAssertNil(tree.subtree(rootedAt: 1))
    }

    func testSingleProcessIsARootWithNoChildren() {
        let alone = row(pid: 42, name: "Safari", parentPid: nil)
        let tree = ProcessTree.build(from: [alone])
        let node = tree.subtree(rootedAt: 42)

        XCTAssertEqual(node?.row, alone)
        XCTAssertEqual(node?.isPlaceholder, false)
        XCTAssertNil(node?.placeholderPid)
        XCTAssertEqual(node?.children, [])
        XCTAssertEqual(tree.ancestors(of: 42), [])
        XCTAssertNil(tree.subtree(rootedAt: 7))
    }

    func testLaunchdWithParentZeroIsARootNotAPlaceholder() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let tree = ProcessTree.build(from: [launchd])
        let node = tree.subtree(rootedAt: 1)

        XCTAssertEqual(node?.row, launchd)
        XCTAssertEqual(node?.isPlaceholder, false)
        XCTAssertNil(node?.placeholderPid)
        XCTAssertEqual(node?.children, [])
        XCTAssertEqual(tree.ancestors(of: 1), [])
        XCTAssertNil(tree.subtree(rootedAt: 0))
        XCTAssertEqual(tree.ancestors(of: 0), [])
    }

    func testChildrenFollowTheParentInInputOrder() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let windowServer = row(pid: 20, name: "WindowServer", parentPid: 1)
        let loginWindow = row(pid: 10, name: "loginwindow", parentPid: 1)
        let tree = ProcessTree.build(from: [launchd, windowServer, loginWindow])
        let root = tree.subtree(rootedAt: 1)

        XCTAssertEqual(root?.row, launchd)
        XCTAssertEqual(root?.children.map { $0.row?.pid }, [20, 10])
        XCTAssertEqual(root?.children.map { $0.row?.name }, ["WindowServer", "loginwindow"])
        XCTAssertEqual(root?.children.map(\.isPlaceholder), [false, false])
        XCTAssertEqual(root?.children[0].children, [])
        XCTAssertEqual(root?.children[1].children, [])
        XCTAssertEqual(tree.subtree(rootedAt: 20)?.row, windowServer)
        XCTAssertEqual(tree.subtree(rootedAt: 20)?.children, [])
    }

    func testAncestorsListTheDirectParentBeforeTheRoot() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let mid = row(pid: 10, name: "WindowServer", parentPid: 1)
        let leaf = row(pid: 30, name: "Safari", parentPid: 10)
        let tree = ProcessTree.build(from: [launchd, mid, leaf])

        XCTAssertEqual(tree.ancestors(of: 30).map { $0.row?.pid }, [10, 1])
        XCTAssertEqual(tree.ancestors(of: 30).map { $0.row?.name }, ["WindowServer", "launchd"])
        XCTAssertEqual(tree.ancestors(of: 30).map(\.isPlaceholder), [false, false])
        XCTAssertEqual(tree.ancestors(of: 10).map { $0.row?.pid }, [1])
        XCTAssertEqual(tree.ancestors(of: 1), [])
        XCTAssertEqual(tree.ancestors(of: 99), [])
    }

    func testSubtreeIncludesEveryDescendant() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let mid = row(pid: 10, name: "WindowServer", parentPid: 1)
        let leaf = row(pid: 30, name: "Safari", parentPid: 10)
        let tree = ProcessTree.build(from: [launchd, mid, leaf])
        let root = tree.subtree(rootedAt: 1)

        XCTAssertEqual(root?.row?.pid, 1)
        XCTAssertEqual(root?.children.map { $0.row?.pid }, [10])
        XCTAssertEqual(root?.children.first?.children.map { $0.row?.pid }, [30])
        XCTAssertEqual(root?.children.first?.children.first?.children, [])
        XCTAssertEqual(tree.subtree(rootedAt: 30)?.row, leaf)
        XCTAssertEqual(tree.subtree(rootedAt: 30)?.children, [])
        XCTAssertNil(tree.subtree(rootedAt: 99))
    }

    func testChildOrderFollowsRowAppearanceEvenWhenTheParentComesLast() {
        let first = row(pid: 10, name: "loginwindow", parentPid: 1)
        let second = row(pid: 20, name: "WindowServer", parentPid: 1)
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let tree = ProcessTree.build(from: [first, second, launchd])

        XCTAssertEqual(tree.subtree(rootedAt: 1)?.children.map { $0.row?.pid }, [10, 20])
        XCTAssertEqual(tree.ancestors(of: 20).map { $0.row?.pid }, [1])
        XCTAssertEqual(tree.ancestors(of: 1), [])
    }

    func testMissingNonZeroParentBecomesAPlaceholderRoot() {
        let worker = row(pid: 50, name: "worker", parentPid: 123)
        let tree = ProcessTree.build(from: [worker])
        let placeholder = tree.subtree(rootedAt: 123)

        XCTAssertEqual(placeholder?.isPlaceholder, true)
        XCTAssertNil(placeholder?.row)
        XCTAssertEqual(placeholder?.placeholderPid, 123)
        XCTAssertEqual(placeholder?.children.map { $0.row?.pid }, [50])
        XCTAssertEqual(placeholder?.children.first?.row, worker)
        XCTAssertEqual(placeholder?.children.first?.isPlaceholder, false)
        XCTAssertNil(placeholder?.children.first?.placeholderPid)
        XCTAssertEqual(tree.ancestors(of: 50).map(\.isPlaceholder), [true])
        XCTAssertEqual(tree.ancestors(of: 50).map(\.placeholderPid), [123])
        XCTAssertNil(tree.ancestors(of: 50).first?.row)
        XCTAssertEqual(tree.ancestors(of: 123), [])
    }

    func testPlaceholderTextNamesTheMissingPid() {
        let worker = row(pid: 50, name: "worker", parentPid: 123)
        let other = row(pid: 8, name: "other", parentPid: 456)
        let tree = ProcessTree.build(from: [worker])
        let otherTree = ProcessTree.build(from: [other])

        XCTAssertEqual(tree.subtree(rootedAt: 123)?.placeholderText(), "(PID 123 - 无权限)")
        XCTAssertEqual(otherTree.subtree(rootedAt: 456)?.placeholderText(), "(PID 456 - 无权限)")
        XCTAssertNil(tree.subtree(rootedAt: 50)?.placeholderText())
    }

    func testSiblingsUnderOnePlaceholderKeepInputOrder() {
        let first = row(pid: 2, name: "a", parentPid: 9)
        let second = row(pid: 3, name: "b", parentPid: 9)
        let tree = ProcessTree.build(from: [first, second])
        let placeholder = tree.subtree(rootedAt: 9)

        XCTAssertEqual(placeholder?.isPlaceholder, true)
        XCTAssertEqual(placeholder?.children.map { $0.row?.pid }, [2, 3])
        XCTAssertEqual(placeholder?.children.map { $0.row?.name }, ["a", "b"])
        XCTAssertEqual(tree.ancestors(of: 2).map(\.placeholderPid), [9])
        XCTAssertEqual(tree.ancestors(of: 3).map(\.placeholderPid), [9])
        XCTAssertEqual(tree.ancestors(of: 9), [])
    }

    func testAncestorsCrossARealParentThenThePlaceholder() {
        let worker = row(pid: 50, name: "worker", parentPid: 123)
        let helper = row(pid: 51, name: "helper", parentPid: 50)
        let tree = ProcessTree.build(from: [worker, helper])
        let chain = tree.ancestors(of: 51)

        XCTAssertEqual(chain.map(\.isPlaceholder), [false, true])
        XCTAssertEqual(chain.first?.row?.pid, 50)
        XCTAssertEqual(chain.first?.row?.name, "worker")
        XCTAssertEqual(chain.last?.placeholderPid, 123)
        XCTAssertNil(chain.last?.row)
        XCTAssertEqual(chain.last?.placeholderText(), "(PID 123 - 无权限)")
        XCTAssertEqual(tree.subtree(rootedAt: 123)?.children.map { $0.row?.pid }, [50])
        XCTAssertEqual(tree.subtree(rootedAt: 50)?.children.map { $0.row?.pid }, [51])
        XCTAssertEqual(tree.ancestors(of: 123), [])
    }

    func testDuplicatePidKeepsTheFirstRow() {
        let first = row(pid: 4, name: "first", parentPid: nil, memory: 100)
        let second = row(pid: 4, name: "second", parentPid: 1, memory: 200)
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let tree = ProcessTree.build(from: [first, second, launchd])

        XCTAssertEqual(tree.subtree(rootedAt: 4)?.row?.name, "first")
        XCTAssertEqual(tree.subtree(rootedAt: 4)?.row?.memoryBytes, 100)
        XCTAssertEqual(tree.subtree(rootedAt: 4)?.row?.parentPid, nil)
        XCTAssertEqual(tree.ancestors(of: 4), [])
        XCTAssertEqual(tree.subtree(rootedAt: 1)?.children, [])
    }

    func testDuplicatePidDoesNotAppearTwiceAmongChildren() {
        let parent = row(pid: 1, name: "launchd", parentPid: 0)
        let kept = row(pid: 2, name: "a", parentPid: 1, memory: 10)
        let dropped = row(pid: 2, name: "dup", parentPid: 1, memory: 99)
        let sibling = row(pid: 3, name: "b", parentPid: 1)
        let tree = ProcessTree.build(from: [parent, kept, dropped, sibling])

        XCTAssertEqual(tree.subtree(rootedAt: 1)?.children.map { $0.row?.pid }, [2, 3])
        XCTAssertEqual(tree.subtree(rootedAt: 1)?.children.map { $0.row?.name }, ["a", "b"])
        XCTAssertEqual(tree.subtree(rootedAt: 2)?.row?.memoryBytes, 10)
    }

    func testSelfParentDropsTheEdgeAndStaysARoot() {
        let loop = row(pid: 5, name: "loop", parentPid: 5)
        let tree = ProcessTree.build(from: [loop])
        let node = tree.subtree(rootedAt: 5)

        XCTAssertEqual(node?.row, loop)
        XCTAssertEqual(node?.isPlaceholder, false)
        XCTAssertNil(node?.placeholderPid)
        XCTAssertEqual(node?.children, [])
        XCTAssertEqual(tree.ancestors(of: 5), [])
    }

    func testMutualParentsDropTheLaterEdge() {
        let a = row(pid: 1, name: "a", parentPid: 2)
        let b = row(pid: 2, name: "b", parentPid: 1)
        let tree = ProcessTree.build(from: [a, b])

        XCTAssertEqual(tree.subtree(rootedAt: 2)?.row?.name, "b")
        XCTAssertEqual(tree.subtree(rootedAt: 2)?.children.map { $0.row?.pid }, [1])
        XCTAssertEqual(tree.subtree(rootedAt: 2)?.children.first?.children, [])
        XCTAssertEqual(tree.subtree(rootedAt: 1)?.children, [])
        XCTAssertEqual(tree.ancestors(of: 1).map { $0.row?.pid }, [2])
        XCTAssertEqual(tree.ancestors(of: 2), [])
    }

    func testThreeCycleDropsTheClosingEdge() {
        let a = row(pid: 1, name: "a", parentPid: 2)
        let b = row(pid: 2, name: "b", parentPid: 3)
        let c = row(pid: 3, name: "c", parentPid: 1)
        let tree = ProcessTree.build(from: [a, b, c])

        XCTAssertEqual(tree.subtree(rootedAt: 3)?.children.map { $0.row?.pid }, [2])
        XCTAssertEqual(tree.subtree(rootedAt: 2)?.children.map { $0.row?.pid }, [1])
        XCTAssertEqual(tree.subtree(rootedAt: 1)?.children, [])
        XCTAssertEqual(tree.ancestors(of: 1).map { $0.row?.pid }, [2, 3])
        XCTAssertEqual(tree.ancestors(of: 2).map { $0.row?.pid }, [3])
        XCTAssertEqual(tree.ancestors(of: 3), [])
    }

    func testDroppedCycleEdgeKeepsAnUnrelatedChild() {
        let a = row(pid: 1, name: "a", parentPid: 2)
        let b = row(pid: 2, name: "b", parentPid: 1)
        let c = row(pid: 3, name: "c", parentPid: 1)
        let tree = ProcessTree.build(from: [a, b, c])

        XCTAssertEqual(tree.subtree(rootedAt: 2)?.children.map { $0.row?.pid }, [1])
        XCTAssertEqual(tree.subtree(rootedAt: 1)?.children.map { $0.row?.pid }, [3])
        XCTAssertEqual(tree.subtree(rootedAt: 1)?.children.first?.children, [])
        XCTAssertEqual(tree.ancestors(of: 3).map { $0.row?.pid }, [1, 2])
        XCTAssertEqual(tree.ancestors(of: 2), [])
    }

    func testInitiallyExpandedIncludesEveryAncestorAndTheCenter() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let mid = row(pid: 10, name: "WindowServer", parentPid: 1)
        let center = row(pid: 30, name: "Safari", parentPid: 10)
        let worker = row(pid: 50, name: "worker", parentPid: 80)
        let tree = ProcessTree.build(from: [launchd, mid, center, worker])

        XCTAssertEqual(tree.initiallyExpanded(centeredOn: 30), [1, 10, 30])
        XCTAssertEqual(tree.initiallyExpanded(centeredOn: 50), [80, 50])
    }

    func testInitiallyExpandedIncludesDirectChildrenOfTheCenter() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let center = row(pid: 10, name: "Safari", parentPid: 1)
        let childA = row(pid: 20, name: "GPU", parentPid: 10)
        let childB = row(pid: 21, name: "Networking", parentPid: 10)
        let tree = ProcessTree.build(from: [launchd, center, childA, childB])

        XCTAssertEqual(tree.initiallyExpanded(centeredOn: 10), [1, 10, 20, 21])
    }

    func testInitiallyExpandedOmitsGrandchildren() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let center = row(pid: 10, name: "Safari", parentPid: 1)
        let child = row(pid: 20, name: "GPU", parentPid: 10)
        let grandchild = row(pid: 30, name: "helper", parentPid: 20)
        let tree = ProcessTree.build(from: [launchd, center, child, grandchild])

        let expanded = tree.initiallyExpanded(centeredOn: 10)
        XCTAssertTrue(expanded.contains(20))
        XCTAssertFalse(expanded.contains(30))
    }

    func testInitiallyExpandedOmitsAncestorSideBranches() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let mid = row(pid: 10, name: "WindowServer", parentPid: 1)
        let side = row(pid: 11, name: "loginwindow", parentPid: 1)
        let sideChild = row(pid: 12, name: "login-helper", parentPid: 11)
        let center = row(pid: 30, name: "Safari", parentPid: 10)
        let child = row(pid: 40, name: "GPU", parentPid: 30)
        let tree = ProcessTree.build(from: [launchd, mid, side, sideChild, center, child])

        let expanded = tree.initiallyExpanded(centeredOn: 30)
        XCTAssertFalse(expanded.contains(11))
        XCTAssertFalse(expanded.contains(12))
        XCTAssertEqual(expanded, [1, 10, 30, 40])
    }

    func testInitiallyExpandedIsEmptyForAnUnknownPid() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let tree = ProcessTree.build(from: [launchd])

        XCTAssertEqual(tree.initiallyExpanded(centeredOn: 99), [])
        XCTAssertEqual(tree.initiallyExpanded(centeredOn: 0), [])
        XCTAssertEqual(ProcessTree.build(from: []).initiallyExpanded(centeredOn: 1), [])
    }

    func testNodePidUsesTheRowOtherwiseThePlaceholder() {
        let alone = row(pid: 42, name: "Safari", parentPid: nil)
        let tree = ProcessTree.build(from: [alone])
        XCTAssertEqual(tree.subtree(rootedAt: 42)?.pid, 42)

        let worker = row(pid: 50, name: "worker", parentPid: 123)
        let missing = ProcessTree.build(from: [worker])
        XCTAssertEqual(missing.subtree(rootedAt: 123)?.pid, 123)
        XCTAssertEqual(missing.subtree(rootedAt: 50)?.pid, 50)
    }

    func testMemoryPageTurnsRisingOnlyOffWhenThePidHasNoBadge() {
        let next = ProcessTree.filtersAfterFocus(
            pid: 7,
            page: .memory,
            risingOnly: true,
            windowedOnly: true,
            rows: [],
            nameQuery: "",
            seriesByPid: [:],
            windowedPids: { [7] }
        )

        XCTAssertFalse(next.risingOnly)
        XCTAssertTrue(next.windowedOnly)
    }

    func testMemoryPageKeepsWindowedOnlyWhenThePidCanOpenAWindow() {
        let next = ProcessTree.filtersAfterFocus(
            pid: 7,
            page: .memory,
            risingOnly: false,
            windowedOnly: true,
            rows: [],
            nameQuery: "Safari",
            seriesByPid: [:],
            windowedPids: { [7, 8] }
        )

        XCTAssertFalse(next.risingOnly)
        XCTAssertTrue(next.windowedOnly)
    }

    func testMemoryPageTurnsWindowedOnlyOffWhenThePidCannotOpenAWindow() {
        let next = ProcessTree.filtersAfterFocus(
            pid: 7,
            page: .memory,
            risingOnly: false,
            windowedOnly: true,
            rows: [],
            nameQuery: "",
            seriesByPid: [:],
            windowedPids: { [8] }
        )

        XCTAssertFalse(next.risingOnly)
        XCTAssertFalse(next.windowedOnly)
    }

    func testCPUPageKeepsRisingOnlyAndWindowedOnly() {
        let next = ProcessTree.filtersAfterFocus(
            pid: 7,
            page: .cpu,
            risingOnly: true,
            windowedOnly: true,
            rows: [],
            nameQuery: "no-match",
            seriesByPid: [:],
            windowedPids: { [] }
        )

        XCTAssertTrue(next.risingOnly)
        XCTAssertTrue(next.windowedOnly)
    }

    func testMemoryPageKeepsRisingOnlyWhenThePidHasABadge() {
        let series = risingSeries()
        XCTAssertNotNil(MemoryGrowthList.badge(page: .memory, rowPid: 7, seriesByPid: [7: series]))

        let next = ProcessTree.filtersAfterFocus(
            pid: 7,
            page: .memory,
            risingOnly: true,
            windowedOnly: true,
            rows: [],
            nameQuery: "not-this-process",
            seriesByPid: [7: series],
            windowedPids: { [] }
        )

        XCTAssertTrue(next.risingOnly)
        XCTAssertFalse(next.windowedOnly)
    }

    func testParentZeroIsNotAPlaceholderBesideAMissingParent() {
        let launchd = row(pid: 1, name: "launchd", parentPid: 0)
        let worker = row(pid: 50, name: "worker", parentPid: 80)
        let tree = ProcessTree.build(from: [launchd, worker])

        XCTAssertNil(tree.subtree(rootedAt: 0))
        XCTAssertEqual(tree.ancestors(of: 0), [])
        XCTAssertEqual(tree.subtree(rootedAt: 1)?.isPlaceholder, false)
        XCTAssertEqual(tree.ancestors(of: 1), [])
        XCTAssertEqual(tree.subtree(rootedAt: 80)?.placeholderText(), "(PID 80 - 无权限)")
        XCTAssertEqual(tree.subtree(rootedAt: 80)?.children.map { $0.row?.pid }, [50])
        XCTAssertEqual(tree.ancestors(of: 80), [])
    }

    private func risingSeries() -> [ChartSample] {
        let baseline = 200_000_000.0
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let step = 1_048_576.0
        return (0..<MemoryGrowthSignal.minSamples).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index) * 1.5),
                value: baseline + Double(index) * step
            )
        }
    }

    private func row(pid: Int32, name: String, parentPid: Int32?, memory: UInt64 = 4096) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: memory,
            threadCount: 1,
            parentPid: parentPid
        )
    }
}
