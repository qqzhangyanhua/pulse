import Foundation

/// One retry chrome for every failure empty state. No second page-specific chrome.
///
/// Locked by TECH #43 / #44. Seven empties and `*PageCopy` read these strings.
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

/// Retry-visible VM slice. Click does not clear; `accept` false does not write.
enum SamplingRetryApply {
    struct Held: Equatable, Sendable {
        var loadState: LoadState
        var samplingFailed: Bool
        var processListFailed: Bool
        var hasSnapshot: Bool
    }

    static func loadState(
        accepted: Bool,
        sampleSucceeded: Bool,
        hasSnapshot: Bool
    ) -> LoadState? {
        guard accepted else { return nil }
        if sampleSucceeded { return .ready }
        return hasSnapshot ? .ready : .failed
    }

    /// Manual retry click: keep the failure phase and flags. Never `.sampling`.
    static func afterManualRetry(_ held: Held) -> Held {
        Held(
            loadState: SamplingRetryChrome.loadStateDuringRetry(held.loadState),
            samplingFailed: held.samplingFailed,
            processListFailed: held.processListFailed,
            hasSnapshot: held.hasSnapshot
        )
    }

    /// `nil` = stale / cancelled: caller writes nothing.
    static func apply(
        _ held: Held,
        accepted: Bool,
        sampleSucceeded: Bool
    ) -> Held? {
        guard let loadState = loadState(
            accepted: accepted,
            sampleSucceeded: sampleSucceeded,
            hasSnapshot: held.hasSnapshot
        ) else {
            return nil
        }
        var next = held
        next.loadState = loadState
        next.samplingFailed = !sampleSucceeded
        if sampleSucceeded {
            next.hasSnapshot = true
        }
        return next
    }
}

/// Empty-state button / pending line from `gate.retrying`. One chrome, seven call sites.
struct SamplingRetryEmptyChrome: Equatable, Sendable {
    let buttonTitle: String
    let isButtonEnabled: Bool
    let pendingMessage: String?

    init(retrying: Bool) {
        buttonTitle = SamplingRetryChrome.buttonTitle
        isButtonEnabled = SamplingRetryChrome.isButtonEnabled(retrying: retrying)
        pendingMessage = SamplingRetryChrome.showsPendingLine(retrying: retrying)
            ? SamplingRetryChrome.pendingLine
            : nil
    }
}
