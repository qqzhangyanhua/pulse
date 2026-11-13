import Foundation
import Security
import ServiceManagement

/// Lists the three launch-item directories and asks for each legacy plist status.
/// A directory that cannot be listed stays a 「—」 row.
enum LaunchItemReader {
    static func read() -> [LaunchItemRow] {
        LaunchItemList.rows(from: [
            listing(url: userAgentsURL(), source: LaunchItemCopy.userAgents),
            listing(
                url: URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
                source: LaunchItemCopy.localAgents
            ),
            listing(
                url: URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true),
                source: LaunchItemCopy.localDaemons
            ),
        ])
    }

    private static func userAgentsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    /// Top level only. A thrown listing is an unreadable directory, not an empty one.
    private static func listing(url: URL, source: String) -> LaunchItemDirectoryRead {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return LaunchItemDirectoryRead(source: source, files: nil)
        }
        let files = urls
            .filter { $0.pathExtension.lowercased() == "plist" }
            .filter { !isDirectory($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { file(at: $0) }
        return LaunchItemDirectoryRead(source: source, files: files)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private static func file(at url: URL) -> LaunchItemFile {
        let data = (try? Data(contentsOf: url)) ?? Data()
        let decoded = LaunchItemPlistDecoder.row(fileName: url.lastPathComponent, data: data)
        let facts = decoded.programPath == LaunchItemCopy.missing ? nil : signingFacts(at: decoded.programPath)
        return LaunchItemFile(
            fileName: url.lastPathComponent,
            data: data,
            status: status(at: url),
            signature: facts
        )
    }

    /// `.notFound` is an unreadable status, so the row shows 「—」.
    private static func status(at url: URL) -> LaunchItemStatus? {
        switch SMAppService.statusForLegacyPlist(at: url) {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return nil
        @unknown default:
            return nil
        }
    }

    /// `kSecCSSigningInformation` (`1 << 1`). Nil when the static code cannot be copied.
    private static func signingFacts(at path: String) -> ProcessSigningFacts? {
        var staticCode: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            SecCSFlags(rawValue: 0),
            &staticCode
        )
        guard created == errSecSuccess, let staticCode else { return nil }

        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: 1 << 1),
            &information
        )
        if status == errSecCSUnsigned {
            return ProcessSigningFacts(
                status: status,
                teamIdentifier: nil,
                certificateSummaries: [],
                flags: 0
            )
        }
        guard let information else {
            return ProcessSigningFacts(
                status: status,
                teamIdentifier: nil,
                certificateSummaries: [],
                flags: 0
            )
        }
        let info = information as NSDictionary
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return ProcessSigningFacts(
            status: status,
            teamIdentifier: team,
            certificateSummaries: summaries(in: info),
            flags: flags
        )
    }

    private static func summaries(in info: NSDictionary) -> [String] {
        guard let certificates = info[kSecCodeInfoCertificates as String] as? NSArray else { return [] }
        var result: [String] = []
        for item in certificates {
            let value = item as CFTypeRef
            guard CFGetTypeID(value) == SecCertificateGetTypeID() else { continue }
            let certificate = value as! SecCertificate
            if let summary = SecCertificateCopySubjectSummary(certificate) as String? {
                result.append(summary)
            }
        }
        return result
    }
}
