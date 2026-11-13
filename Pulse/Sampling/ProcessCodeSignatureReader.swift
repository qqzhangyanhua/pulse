import Darwin
import Foundation
import Security

/// Signature facts and `kinfo_proc` flags for one pid.
/// Called when the selected pid changes, not on the sampling tick.
struct ProcessCodeReading: Equatable, Sendable {
    var facts: ProcessSigningFacts?
    var processFlags: UInt32?
}

enum ProcessCodeSignatureReader {
    /// `kSecCSSigningInformation` (`1 << 1`).
    private static let signingInformation = SecCSFlags(rawValue: 1 << 1)

    static func read(pid: Int32) -> ProcessCodeReading {
        ProcessCodeReading(
            facts: signatureFacts(pid: pid),
            processFlags: processFlags(pid: pid)
        )
    }

    /// Nil when the guest or its static code cannot be copied. An unsigned guest is facts, not nil.
    private static func signatureFacts(pid: Int32) -> ProcessSigningFacts? {
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        let guestStatus = SecCodeCopyGuestWithAttributes(
            nil,
            attributes,
            SecCSFlags(rawValue: 0),
            &guest
        )
        guard guestStatus == errSecSuccess, let guest else { return nil }

        // Signing information takes a static code. The guest from the pid is a dynamic code.
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(guest, SecCSFlags(rawValue: 0), &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else { return nil }

        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(staticCode, signingInformation, &information)
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

    /// Leaf certificate first, as `kSecCodeInfoCertificates` returns them.
    private static func summaries(in info: NSDictionary) -> [String] {
        guard let certificates = info[kSecCodeInfoCertificates as String] as? NSArray else { return [] }
        var result: [String] = []
        for item in certificates {
            guard let certificate = item as? SecCertificate else { continue }
            if let summary = SecCertificateCopySubjectSummary(certificate) as String? {
                result.append(summary)
            }
        }
        return result
    }

    /// `P_TRANSLATED` lives in `kp_proc.p_flag`. A failed sysctl stays missing.
    private static func processFlags(pid: Int32) -> UInt32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let status = mib.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return sysctl(base, u_int(buffer.count), &info, &size, nil, 0)
        }
        guard status == 0 else { return nil }
        return UInt32(truncatingIfNeeded: info.kp_proc.p_flag)
    }
}
