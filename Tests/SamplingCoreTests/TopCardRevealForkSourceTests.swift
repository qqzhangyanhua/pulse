import XCTest

/// Source evidence for the card-pid versus group-representative fork.
/// Linux reads text. This file does not execute `TopConsumer.leading`.
final class TopCardRevealForkSourceTests: XCTestCase {
    func testCardTieAndCombineTieAreDifferentComparisons() throws {
        let cards = try repoText("Pulse/Views/OverviewCards.swift")
        XCTAssertTrue(cards.contains("import SwiftUI"))
        XCTAssertTrue(cards.contains("struct TopConsumer"))
        XCTAssertTrue(cards.contains("static func leading(in rows: [ProcessRow])"))
        XCTAssertTrue(cards.contains("if row.memoryBytes >= bucket.bestMemory"))
        XCTAssertTrue(cards.contains("bucket.pid = row.pid"))

        let projection = try repoText("Pulse/Models/AppGroupProjection.swift")
        let combine = try functionBody(named: "combine", in: projection)
        XCTAssertTrue(combine.contains("return lhs.pid > rhs.pid"))
        XCTAssertFalse(combine.contains("TopConsumer"))

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertFalse(package.contains("OverviewCards.swift"))
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

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["static func \(name)(", "func \(name)("]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw ForkSourceError.missing(name)
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        var depth = 0
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...cursor]) }
            }
            cursor = source.index(after: cursor)
        }
        throw ForkSourceError.missing("balanced brace for \(label)")
    }
}

private enum ForkSourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
