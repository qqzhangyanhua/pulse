import SwiftUI

struct ProcessTreeView: View {
    let rows: [ProcessRow]
    let centerPid: Int32
    @Binding var expandedPids: Set<Int32>
    let onBack: () -> Void
    let onSelect: (Int32) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProcessTreeBackButton(action: onBack)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleNodes) { item in
                        ProcessTreeNodeRow(
                            item: item,
                            isCenter: item.pid == centerPid,
                            isExpanded: expandedPids.contains(item.pid),
                            onToggle: { toggle(item.pid) },
                            onSelect: onSelect
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var visibleNodes: [ProcessTreeVisibleNode] {
        let tree = ProcessTree.build(from: rows)
        guard let root = rootNode(in: tree) else { return [] }
        return flatten(root, depth: 0)
    }

    private func rootNode(in tree: ProcessTree) -> ProcessTreeNode? {
        guard tree.subtree(rootedAt: centerPid) != nil else { return nil }
        guard let ancestor = tree.ancestors(of: centerPid).last else {
            return tree.subtree(rootedAt: centerPid)
        }
        guard let rootPid = ancestor.row?.pid ?? ancestor.placeholderPid else { return nil }
        return tree.subtree(rootedAt: rootPid)
    }

    private func flatten(_ node: ProcessTreeNode, depth: Int) -> [ProcessTreeVisibleNode] {
        guard let pid = node.row?.pid ?? node.placeholderPid else { return [] }
        let item = ProcessTreeVisibleNode(pid: pid, node: node, depth: depth)
        guard expandedPids.contains(pid) else { return [item] }
        let children = node.children.flatMap { flatten($0, depth: depth + 1) }
        return [item] + children
    }

    private func toggle(_ pid: Int32) {
        if expandedPids.contains(pid) {
            expandedPids.remove(pid)
        } else {
            expandedPids.insert(pid)
        }
    }
}

private struct ProcessTreeVisibleNode: Identifiable {
    let pid: Int32
    let node: ProcessTreeNode
    let depth: Int

    var id: Int32 { pid }
}

private struct ProcessTreeNodeRow: View {
    let item: ProcessTreeVisibleNode
    let isCenter: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelect: (Int32) -> Void

    var body: some View {
        HStack(spacing: 4) {
            disclosure
            content
        }
        .padding(.leading, CGFloat(item.depth) * 16)
        .padding(.vertical, 3)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }

    @ViewBuilder
    private var disclosure: some View {
        if item.node.children.isEmpty {
            Color.clear.frame(width: 16, height: 16)
        } else {
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "折叠" : "展开")
        }
    }

    private var content: some View {
        Group {
            if let row = item.node.row {
                Button {
                    onSelect(row.pid)
                } label: {
                    HStack(spacing: 8) {
                        Text(row.name)
                            .lineLimit(1)
                        Text("PID \(row.pid)")
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                        Spacer(minLength: 8)
                        Text(ByteFormat.memory(row.memoryBytes))
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else if let placeholder = item.node.placeholderText() {
                HStack(spacing: 8) {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isCenter ? PulsePalette.selection : Color.clear)
    }
}

struct ProcessTreeOpenButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(help)
    }
}

private struct ProcessTreeBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("返回")
            }
        }
        .buttonStyle(.plain)
    }
}
