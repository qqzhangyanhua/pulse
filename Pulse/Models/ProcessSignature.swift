import Foundation

/// Facts copied out of a SecCode signing-info dictionary. No Security types.
struct ProcessSigningFacts: Equatable, Sendable {
    /// `SecCodeCopySigningInformation` OSStatus. Zero is a successful read.
    var status: Int32
    var teamIdentifier: String?
    /// Certificate subject summaries, leaf first.
    var certificateSummaries: [String]
    /// `kSecCodeInfoFlags`. Bit 0x2 is an ad-hoc signature.
    var flags: UInt32
}

enum ProcessSignatureDecoder {
    /// `errSecSuccess`.
    private static let success: Int32 = 0
    /// `errSecCSUnsigned`.
    private static let unsigned: Int32 = -67062
    /// `kSecCodeSignatureAdhoc`.
    private static let adhocFlag: UInt32 = 0x2
    /// Leaf subjects for an Apple platform binary, not a developer certificate.
    private static let appleLeaves: Set<String> = [
        "Software Signing",
        "Apple Software Signing",
    ]

    static func text(for facts: ProcessSigningFacts?) -> String {
        guard let facts else { return "—" }
        if facts.status == unsigned || facts.flags & adhocFlag != 0 { return "未签名" }
        guard facts.status == success else { return "—" }
        if let name = developerName(facts) {
            return "开发者：\(name)"
        }
        guard let leaf = facts.certificateSummaries.first, appleLeaves.contains(leaf) else {
            return "—"
        }
        return "Apple"
    }

    /// Team name from the leaf summary, otherwise the team identifier.
    private static func developerName(_ facts: ProcessSigningFacts) -> String? {
        if let summary = facts.certificateSummaries.first, let parsed = teamName(in: summary) {
            return parsed
        }
        guard let team = facts.teamIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !team.isEmpty
        else { return nil }
        return team
    }

    private static func teamName(in summary: String) -> String? {
        guard let colon = summary.range(of: ": ") else { return nil }
        let rest = summary[colon.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        guard let open = rest.lastIndex(of: "("), rest.hasSuffix(")"), open > rest.startIndex else {
            return rest
        }
        let name = rest[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
