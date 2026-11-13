import Combine
import UserNotifications

/// Rule state stays here so a failed frame can pass nil without growing the view model.
@MainActor
final class PressureNoticeCenter: NSObject, UNUserNotificationCenterDelegate {
    static let requestIdentifier = "pulse.pressureNotice"

    private weak var dashboard: MemoryDashboardVM?
    private var cancellable: AnyCancellable?
    private var ruleState = AlertRule.State.armed
    private var customEngine = AlertRuleEngine()
    private var lastCapturedAt: Date?
    private var openMemoryPage: () -> Void = {}
    private var openCustomRule: (DashboardPage, Int32?) -> Void = { _, _ in }

    func install(
        openMemoryPage: @escaping () -> Void,
        openCustomRule: @escaping (DashboardPage, Int32?) -> Void
    ) {
        self.openMemoryPage = openMemoryPage
        self.openCustomRule = openCustomRule
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
        if decision.send {
            let name = TopConsumer.leading(in: dashboard.rows)?.name
            post(PressureNoticeCopy.body(heaviestAppName: name))
        }
        guard accepted, let capturedAt else { return }
        postCustomRules(at: capturedAt)
    }

    /// Custom rules run only on an accepted frame. A failed sample leaves their state alone.
    private func postCustomRules(at date: Date) {
        guard let dashboard else { return }
        let stored = UserDefaults.standard.string(forKey: AlertRuleStore.defaultsKey) ?? ""
        let rules = AlertRuleStore.catalog(stored: stored).custom
        let notices = customEngine.evaluate(rules: rules, frame: alertFrame(dashboard), at: date)
        for notice in notices {
            post(
                notice.body,
                identifier: notice.id,
                route: AlertNoticeRoute(page: notice.page, pid: notice.pid)
            )
        }
    }

    private func alertFrame(_ dashboard: MemoryDashboardVM) -> AlertFrame {
        AlertFrame.sampled(
            systemCpuPercent: dashboard.systemCpuPercent,
            usedMemoryBytes: dashboard.snapshot?.usedBytes,
            memoryPressure: dashboard.snapshot?.pressure,
            chipCelsius: dashboard.machinePageCelsius,
            diskFreeBytes: dashboard.machineFacts?.volume.availableBytes,
            processes: dashboard.rows.map { row in
                AlertProcessSample(
                    pid: row.pid,
                    name: row.name,
                    cpuPercent: row.cpuPercent,
                    memoryBytes: row.memoryBytes
                )
            }
        )
    }

    private func post(
        _ body: String,
        identifier: String = Self.requestIdentifier,
        route: AlertNoticeRoute? = nil
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .authorized, .provisional:
                    self.add(body, identifier: identifier, route: route, center: center)
                case .notDetermined:
                    center.requestAuthorization(options: [.alert]) { granted, _ in
                        guard granted else { return }
                        Task { @MainActor in
                            self.add(body, identifier: identifier, route: route, center: center)
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

    private func add(
        _ body: String,
        identifier: String,
        route: AlertNoticeRoute?,
        center: UNUserNotificationCenter
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Pulse"
        content.body = body
        content.interruptionLevel = .passive
        if let route {
            var info: [AnyHashable: Any] = [AlertNoticeRoute.pageKey: route.page.rawValue]
            if let pid = route.pid {
                info[AlertNoticeRoute.pidKey] = String(pid)
            }
            content.userInfo = info
        }
        let request = UNNotificationRequest(
            identifier: identifier,
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
        let info = response.notification.request.content.userInfo
        let page = info[AlertNoticeRoute.pageKey] as? String
        let pid = info[AlertNoticeRoute.pidKey] as? String
        MainActor.assumeIsolated {
            if identifier == Self.requestIdentifier {
                self.openMemoryPage()
            } else if let route = AlertNoticeRoute.decode(page: page, pid: pid) {
                self.openCustomRule(route.page, route.pid)
            }
        }
        completionHandler()
    }
}
