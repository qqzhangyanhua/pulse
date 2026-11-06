import Foundation

enum WiringSourceText {
    static func text(for typeName: String) throws -> String {
        let matches = try files(namedWithPrefix: typeName)
        if matches.count == 1, let only = matches.first {
            return try read(only)
        }
        let main = matches.filter { stem($0) == typeName }
        guard main.count == 1, let mainFile = main.first else {
            throw WiringSourceTextError.missingType(typeName)
        }
        let others = matches
            .filter { stem($0) != typeName }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try joined([mainFile] + others)
    }

    private static func files(namedWithPrefix typeName: String) throws -> [URL] {
        var matches: [URL] = []
        for relative in ["Pulse/ViewModels", "Pulse/Views"] {
            let directory = repoRoot().appendingPathComponent(relative, isDirectory: true)
            let entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            for entry in entries where isSource(entry, prefix: typeName) {
                matches.append(entry)
            }
        }
        return matches
    }

    private static func isSource(_ url: URL, prefix typeName: String) -> Bool {
        url.pathExtension == "swift" && url.lastPathComponent.hasPrefix(typeName)
    }

    private static func stem(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// A newline is inserted only when the previous chunk does not already end in one.
    private static func joined(_ files: [URL]) throws -> String {
        var result = ""
        for file in files {
            let chunk = try read(file)
            if !result.isEmpty && !result.hasSuffix("\n") {
                result.append("\n")
            }
            result.append(chunk)
        }
        return result
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum WiringSourceTextError: Error, CustomStringConvertible {
    case missingType(String)

    var description: String {
        switch self {
        case .missingType(let typeName):
            return "missing wiring source for \(typeName)"
        }
    }
}
