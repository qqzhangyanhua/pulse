import Foundation

protocol PublicIPTransport {
    func body(from url: URL) async throws -> String
}

enum PublicIPLookupError: Error {
    case unavailable
}

/// Idle until a click. Loading ignores another click. Failure keeps no address.
enum PublicIPRequestState: Equatable {
    case idle
    case loading
    case success(address: String, queriedAt: Date)
    case failure

    func begin() -> PublicIPRequestState {
        if case .loading = self { return self }
        return .loading
    }

    func succeed(address: String, at date: Date) -> PublicIPRequestState {
        .success(address: address, queriedAt: date)
    }

    func fail() -> PublicIPRequestState {
        .failure
    }

    /// The caller passes the zone. This function does not look up the current zone.
    static func queriedAtLabel(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "查询于 \(formatter.string(from: date))"
    }
}

enum PublicIPCopy {
    static let rowTitle = "公网 IP"
    static let query = "查询公网 IP"
    static let copy = "复制"
    static let failed = "查询失败"
    static let retry = "重试"
    static let missing = "—"
}

/// Click-driven public address. Primary, then the fallback. Invalid bodies are not addresses.
enum PublicIPLookup {
    static let primaryEndpoint = URL(string: "https://api.ipify.org")!
    static let fallbackEndpoint = URL(string: "https://checkip.amazonaws.com")!

    static func lookup(using transport: any PublicIPTransport) async -> Result<String, Error> {
        for endpoint in [primaryEndpoint, fallbackEndpoint] {
            do {
                let body = try await transport.body(from: endpoint)
                if let address = PublicIPAddress.parse(body) {
                    return .success(address)
                }
            } catch {
                continue
            }
        }
        return .failure(PublicIPLookupError.unavailable)
    }
}

/// Trimmed IPv4 or IPv6 only. HTML and any other body are missing, not an address.
enum PublicIPAddress {
    static func parse(_ body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard isIPv4(trimmed) || isIPv6(trimmed) else { return nil }
        return trimmed
    }

    private static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard part.count >= 1, part.count <= 3, part.allSatisfy(\.isNumber) else { return false }
            if part.count > 1, part.first == "0" { return false }
            guard let value = Int(part), (0...255).contains(value) else { return false }
        }
        return true
    }

    private static func isIPv6(_ text: String) -> Bool {
        guard text.contains(":"), !text.contains("%") else { return false }
        var head = text
        var dottedGroups = 0
        if text.contains(".") {
            guard let colon = text.lastIndex(of: ":") else { return false }
            let tail = String(text[text.index(after: colon)...])
            guard isIPv4(tail) else { return false }
            dottedGroups = 2
            head = String(text[..<colon])
            if head.hasSuffix(":") {
                head.append(":")
            }
        }
        return hexGroupsFit(head, extra: dottedGroups)
    }

    private static func hexGroupsFit(_ text: String, extra: Int) -> Bool {
        let pieces = text.components(separatedBy: "::")
        guard pieces.count <= 2 else { return false }
        let compressed = pieces.count == 2
        let left = groupList(pieces[0])
        let right = compressed ? groupList(pieces[1]) : []
        guard let left, let right else { return false }
        let written = left.count + right.count + extra
        if compressed {
            return written < 8 && left.allSatisfy(isHexGroup) && right.allSatisfy(isHexGroup)
        }
        return written == 8 && left.allSatisfy(isHexGroup)
    }

    private static func groupList(_ side: String) -> [String]? {
        if side.isEmpty { return [] }
        let groups = side.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard !groups.contains("") else { return nil }
        return groups
    }

    private static func isHexGroup(_ group: String) -> Bool {
        guard (1...4).contains(group.count) else { return false }
        return group.allSatisfy(\.isHexDigit)
    }
}
