import Foundation

/// One launch item already turned into calm copy. Missing text is 「—」, not zero.
struct LaunchItemRow: Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    var programPath: String
    var source: String
    var signature: String
    var enabled: String
}

enum LaunchItemCopy {
    static let missing = "—"
    static let title = "启动项"
    static let empty = "没有启动项"
    static let openSettings = "打开系统设置"
    static let userAgents = "用户 LaunchAgents"
    static let localAgents = "本机 LaunchAgents"
    static let localDaemons = "本机 LaunchDaemons"
    static let enabled = "已启用"
    static let notEnabled = "未启用"
    static let needsApproval = "需要批准"

    static func startedLine(label: String) -> String {
        "由 \(label) 启动，退出后可能自动重启"
    }
}

/// Enabled state of one legacy plist. The Darwin reader fills this in.
enum LaunchItemStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
}

/// One plist the directory reader already opened. Status and signature may be missing.
struct LaunchItemFile: Equatable, Sendable {
    var fileName: String
    var data: Data
    var status: LaunchItemStatus?
    var signature: ProcessSigningFacts?
}

/// One of the three launch-item directories. `files == nil` means the directory could not be read.
struct LaunchItemDirectoryRead: Equatable, Sendable {
    var source: String
    var files: [LaunchItemFile]?
}

enum LaunchItemList {
    static func rows(from reads: [LaunchItemDirectoryRead]) -> [LaunchItemRow] {
        reads.enumerated().flatMap { index, read -> [LaunchItemRow] in
            guard let files = read.files else {
                return [LaunchItemRow(
                    id: "unreadable-\(index)",
                    label: LaunchItemCopy.missing,
                    programPath: LaunchItemCopy.missing,
                    source: LaunchItemCopy.missing,
                    signature: LaunchItemCopy.missing,
                    enabled: LaunchItemCopy.missing
                )]
            }
            return files.map { file in
                let decoded = LaunchItemPlistDecoder.row(fileName: file.fileName, data: file.data)
                let signature = decoded.programPath == LaunchItemCopy.missing
                    ? LaunchItemCopy.missing
                    : ProcessSignatureDecoder.text(for: file.signature)
                return LaunchItemRow(
                    id: "\(read.source)|\(file.fileName)",
                    label: decoded.label,
                    programPath: decoded.programPath,
                    source: read.source,
                    signature: signature,
                    enabled: enabledText(file.status)
                )
            }
        }
    }

    private static func enabledText(_ status: LaunchItemStatus?) -> String {
        switch status {
        case .enabled:
            return LaunchItemCopy.enabled
        case .notRegistered:
            return LaunchItemCopy.notEnabled
        case .requiresApproval:
            return LaunchItemCopy.needsApproval
        case .notFound, nil:
            return LaunchItemCopy.missing
        }
    }
}

/// Plist to a row. Source, signature, and enabled state stay 「—」 until a later read fills them.
enum LaunchItemPlistDecoder {
    static func row(fileName: String, data: Data) -> LaunchItemRow {
        let fields = read(data)
        return LaunchItemRow(
            id: fileName,
            label: fields.label,
            programPath: fields.program,
            source: LaunchItemCopy.missing,
            signature: LaunchItemCopy.missing,
            enabled: LaunchItemCopy.missing
        )
    }

    private static func read(_ data: Data) -> (label: String, program: String) {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = dictionary(object)
        else {
            return (LaunchItemCopy.missing, LaunchItemCopy.missing)
        }
        let label = text(dict["Label"]) ?? LaunchItemCopy.missing
        let program = text(dict["Program"]) ?? firstArgument(dict["ProgramArguments"]) ?? LaunchItemCopy.missing
        return (label, program)
    }

    private static func firstArgument(_ value: Any?) -> String? {
        let items: [Any]
        if let list = value as? [Any] {
            items = list
        } else if let list = value as? NSArray {
            items = list.compactMap { $0 }
        } else {
            return nil
        }
        guard let first = items.first else { return nil }
        return text(first)
    }

    private static func dictionary(_ object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] { return dict }
        guard let dict = object as? NSDictionary else { return nil }
        var fields: [String: Any] = [:]
        for (key, value) in dict {
            guard let name = key as? String else { continue }
            fields[name] = value
        }
        return fields
    }

    private static func text(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The launch item whose program path equals `path`.
/// Nil when the path is missing, none match, or more than one path matches. Not a prefix.
func launchItem(forExecutablePath path: String?, items: [LaunchItemRow]) -> LaunchItemRow? {
    guard let path else { return nil }
    let matches = items.filter { $0.programPath == path }
    guard matches.count == 1 else { return nil }
    return matches[0]
}
