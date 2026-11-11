struct ProcessTreeNode: Equatable {
    let row: ProcessRow?
    let placeholderPid: Int32?
    let children: [ProcessTreeNode]

    var pid: Int32? { row?.pid ?? placeholderPid }

    var isPlaceholder: Bool { row == nil }

    func placeholderText() -> String? {
        guard let placeholderPid else { return nil }
        return "(PID \(placeholderPid) - 无权限)"
    }
}

struct ProcessTree {
    private let nodes: [Int32: ProcessTreeNode]
    private let parentOf: [Int32: Int32]

    static func build(from rows: [ProcessRow]) -> ProcessTree {
        var rowByPid: [Int32: ProcessRow] = [:]
        var order: [Int32] = []
        for row in rows where rowByPid[row.pid] == nil {
            rowByPid[row.pid] = row
            order.append(row.pid)
        }

        var childPids: [Int32: [Int32]] = [:]
        var parentOf: [Int32: Int32] = [:]
        var placeholderPids: [Int32] = []
        var placeholderSeen: Set<Int32> = []
        for pid in order {
            guard let parentPid = rowByPid[pid]?.parentPid, parentPid != 0 else { continue }
            // Input order decides which edge closes a cycle. That edge is dropped.
            if closesCycle(linking: pid, to: parentPid, parentOf: parentOf) { continue }
            if rowByPid[parentPid] == nil, placeholderSeen.insert(parentPid).inserted {
                placeholderPids.append(parentPid)
            }
            childPids[parentPid, default: []].append(pid)
            parentOf[pid] = parentPid
        }

        var cache: [Int32: ProcessTreeNode] = [:]
        func make(_ pid: Int32) -> ProcessTreeNode {
            if let cached = cache[pid] { return cached }
            let children = (childPids[pid] ?? []).map { make($0) }
            let built = node(pid, children: children, rowByPid: rowByPid)
            cache[pid] = built
            return built
        }

        var nodes: [Int32: ProcessTreeNode] = [:]
        for pid in order + placeholderPids {
            nodes[pid] = make(pid)
        }
        return ProcessTree(nodes: nodes, parentOf: parentOf)
    }

    func initiallyExpanded(centeredOn pid: Int32) -> Set<Int32> {
        guard nodes[pid] != nil else { return [] }
        var expanded: Set<Int32> = [pid]
        for ancestor in ancestors(of: pid) {
            guard let ancestorPid = ancestor.pid else { continue }
            expanded.insert(ancestorPid)
        }
        for child in nodes[pid]?.children ?? [] {
            guard let childPid = child.pid else { continue }
            expanded.insert(childPid)
        }
        return expanded
    }

    func ancestors(of pid: Int32) -> [ProcessTreeNode] {
        guard nodes[pid] != nil else { return [] }
        var chain: [ProcessTreeNode] = []
        var current = parentOf[pid]
        var seen: Set<Int32> = [pid]
        while let parent = current, seen.insert(parent).inserted, let node = nodes[parent] {
            chain.append(node)
            current = parentOf[parent]
        }
        return chain
    }

    private static func closesCycle(linking pid: Int32, to parentPid: Int32, parentOf: [Int32: Int32]) -> Bool {
        var current: Int32? = parentPid
        var seen: Set<Int32> = [pid]
        while let cursor = current {
            if !seen.insert(cursor).inserted { return true }
            current = parentOf[cursor]
        }
        return false
    }

    private static func node(
        _ pid: Int32,
        children: [ProcessTreeNode],
        rowByPid: [Int32: ProcessRow]
    ) -> ProcessTreeNode {
        if let row = rowByPid[pid] {
            return ProcessTreeNode(row: row, placeholderPid: nil, children: children)
        }
        return ProcessTreeNode(row: nil, placeholderPid: pid, children: children)
    }

    /// Memory-page keeps that would drop `pid` turn off. Other pages stay as passed.
    static func filtersAfterFocus(
        pid: Int32,
        page: DashboardPage,
        risingOnly: Bool,
        windowedOnly: Bool,
        rows: [ProcessRow],
        nameQuery: String,
        seriesByPid: [Int32: [ChartSample]],
        windowedPids: () -> Set<Int32>
    ) -> (risingOnly: Bool, windowedOnly: Bool) {
        let keepsRising = MemoryGrowthRisingFilter.selectedPid(
            current: pid,
            rows: rows,
            nameQuery: nameQuery,
            page: page,
            risingOnly: risingOnly,
            seriesByPid: seriesByPid
        ) == pid
        let keepsWindowed = WindowedAppFilter.selectedPid(
            current: pid,
            page: page,
            windowedOnly: windowedOnly,
            windowedPids: windowedPids
        ) == pid
        return (
            risingOnly: keepsRising ? risingOnly : false,
            windowedOnly: keepsWindowed ? windowedOnly : false
        )
    }

    func subtree(rootedAt pid: Int32) -> ProcessTreeNode? {
        nodes[pid]
    }
}
