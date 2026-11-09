import Foundation

/// Signal chosen after the route has already left AppKit.
enum ProcessQuitSignal: Equatable {
    /// Ordinary quit. POSIX SIGTERM. No extra confirmation.
    case sigterm
    /// Force quit. POSIX SIGKILL. The existing confirmation already returned.
    case sigkill
}

/// How to end a process the sidebar already allowed a quit attempt on.
enum ProcessQuitRoute: Equatable {
    /// `NSRunningApplication` terminate / forceTerminate. Never a signal.
    case application
    /// Do not signal. Map liveness with `refusedResult`.
    case refused
    /// Send this signal, then the existing wait.
    case signal(ProcessQuitSignal)

    /// String prefix. `/Systematic` and `/usr/libexecfoo` are refused, not only children.
    private static let systemPrefixes = ["/System", "/usr/libexec", "/usr/sbin", "/sbin"]

    static func decide(
        hasApplication: Bool,
        executablePath: String?,
        force: Bool
    ) -> ProcessQuitRoute {
        if hasApplication {
            return .application
        }
        if isMissing(executablePath) || isSystemPath(executablePath ?? "") {
            return .refused
        }
        return .signal(force ? .sigkill : .sigterm)
    }

    /// Still alive is the existing request failure. Already gone is not found.
    static func refusedResult(isAlive: Bool) -> ProcessActionResult {
        isAlive ? .requestFailed : .notFound
    }

    /// `kill` ESRCH is not found. Any other failure is the existing request failure.
    static func signalFailure(noSuchProcess: Bool) -> ProcessActionResult {
        noSuchProcess ? .notFound : .requestFailed
    }

    private static func isMissing(_ path: String?) -> Bool {
        guard let path else { return true }
        return path.isEmpty
    }

    private static func isSystemPath(_ path: String) -> Bool {
        systemPrefixes.contains(where: path.hasPrefix)
    }
}
