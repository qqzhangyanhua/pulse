import Foundation

/// One retry chrome for every failure empty state. No second page-specific chrome.
///
/// Locked by TECH #43 / #44. ② applies these to the seven empties and `*PageCopy`.
/// ① does not rewrite Views or today's `*Copy.retry` / failure sentences.
enum SamplingRetryChrome {
    static let buttonTitle = "重试"
    static let pendingLine = "正在重试…"
    static let buttonReference = "点重试再试"
    static let overviewFailureMessage = "这轮采样没有回来，点重试再试。"
    static let processListFailedMessage = "这轮没读到进程列表，点重试再试。"

    static func isButtonEnabled(retrying: Bool) -> Bool {
        !retrying
    }

    static func showsPendingLine(retrying: Bool) -> Bool {
        retrying
    }

    /// Retrying must keep the current failure phase. Never promote `.failed` to `.sampling`.
    static func loadStateDuringRetry(_ current: LoadState) -> LoadState {
        current
    }

    /// Only the button-pointing phrase. Titles and non-pointing sentences stay.
    static func messageByUpdatingButtonReference(_ message: String) -> String {
        message.replacingOccurrences(of: "点重新采样再试", with: buttonReference)
    }
}

/// LoadState write after `accept`. Nil means do not write (stale / cancelled).
/// Success → ready. Failure → failed if there is no snapshot, else keep ready (today's tick).
enum SamplingRetryApply {
    static func loadState(
        accepted: Bool,
        sampleSucceeded: Bool,
        hasSnapshot: Bool
    ) -> LoadState? {
        guard accepted else { return nil }
        if sampleSucceeded { return .ready }
        return hasSnapshot ? .ready : .failed
    }
}
