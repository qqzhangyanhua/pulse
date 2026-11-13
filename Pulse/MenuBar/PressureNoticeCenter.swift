import Combine
import UserNotifications

/// Rule state stays here so a failed frame can pass nil without growing the view model.
@MainActor
final class PressureNoticeCenter: NSObject, UNUserNotificationCenterDelegate {
    static let requestIdentifier = "pulse.pressureNotice"

    private weak var dashboard: MemoryDashboardVM?
    private var cancellable: AnyCancellable?
    private var ruleState = AlertRule.State.armed
    private var lastCapturedAt: Date?
    private var openMemoryPage: () -> Void = {}

    func install(openMemoryPage: @escaping () -> Void) {
        self.openMemoryPage = openMemoryPage
        UNUserNotificationCenter.current().delegate = self
    }

    func observe(_ dashboard: MemoryDashboardVM) {
        self.dashboard = dashboard
        cancellable = dashboard.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.ingest()
            }
        }
    }

    static func requestPermission(then update: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in
            Task { @MainActor in
                readDenied(update)
            }
        }
    }

    static func readDenied(_ update: ((Bool) -> Void)?) {
        guard let update else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor in
                update(denied)
            }
        }
    }

    private func ingest() {
        guard let dashboard else { return }
        let capturedAt = dashboard.snapshot?.capturedAt
        let accepted = capturedAt != nil
            && capturedAt != lastCapturedAt
            && dashboard.samplingFailed == false
        let reading = PressureNoticeReading.pressure(
            accepted: accepted,
            samplingFailed: dashboard.samplingFailed,
            snapshotPressure: dashboard.snapshot?.pressure
        )
        if accepted, let capturedAt {
            lastCapturedAt = capturedAt
        }
        let decision = AlertRule.memoryPressure.advance(
            enabled: PressureNoticePreference.isEnabled(),
            state: ruleState,
            pressure: reading,
            at: capturedAt ?? Date(timeIntervalSince1970: 0)
        )
        ruleState = decision.state
        guard decision.send else { return }
        let name = TopConsumer.leading(in: dashboard.rows)?.name
        post(PressureNoticeCopy.body(heaviestAppName: name))
    }

    private func post(_ body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .authorized, .provisional:
                    self.add(body, center: center)
                case .notDetermined:
                    center.requestAuthorization(options: [.alert]) { granted, _ in
                        guard granted else { return }
                        Task { @MainActor in
                            self.add(body, center: center)
                        }
                    }
                case .denied:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func add(_ body: String, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "Pulse"
        content.body = body
        content.interruptionLevel = .passive
        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: content,
            trigger: nil
        )
        center.add(request) { _ in }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        MainActor.assumeIsolated {
            if identifier == Self.requestIdentifier {
                self.openMemoryPage()
            }
        }
        completionHandler()
    }
}
