import CoreLocation
import Foundation

/// Location permission for the Wi-Fi name. `request()` is the only prompt.
final class HostWiFiLocation: NSObject, CLLocationManagerDelegate {
    private static var active: HostWiFiLocation?
    private let manager = CLLocationManager()
    private let onChange: (WiFiSSIDPermission) -> Void

    private init(onChange: @escaping (WiFiSSIDPermission) -> Void) {
        self.onChange = onChange
        super.init()
    }

    /// Does not prompt. Started next to the connection watch.
    static func start(onChange: @escaping (WiFiSSIDPermission) -> Void) {
        let location = HostWiFiLocation(onChange: onChange)
        active = location
        location.begin()
    }

    static func request() {
        active?.manager.requestWhenInUseAuthorization()
    }

    static func currentPermission() -> WiFiSSIDPermission {
        map(CLLocationManager().authorizationStatus)
    }

    private func begin() {
        manager.delegate = self
        deliver(Self.currentPermission())
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        deliver(Self.map(manager.authorizationStatus))
    }

    private func deliver(_ permission: WiFiSSIDPermission) {
        MainActor.assumeIsolated {
            onChange(permission)
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> WiFiSSIDPermission {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        @unknown default:
            return .denied
        }
    }
}
