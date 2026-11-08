import Foundation

/// This app's own login-item registration. Not a list of other items.
enum LoginItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

struct LoginItemControl: Equatable, Sendable {
    var isOn: Bool
    var caption: String?
    var offersSystemSettings: Bool
}

/// Toggle and caption from the system status. The switch is not a stored bool.
enum LoginItemProjection {
    static let approvalCaption = "需要在系统设置的登录项里允许 Pulse。"
    static let missingCaption = "系统找不到这项登录项。"
    static let openSettingsButton = "打开系统设置"

    static func control(status: LoginItemStatus, registrationError: String?) -> LoginItemControl {
        switch status {
        case .notRegistered:
            return LoginItemControl(isOn: false, caption: shown(registrationError), offersSystemSettings: false)
        case .enabled:
            return LoginItemControl(isOn: true, caption: shown(registrationError), offersSystemSettings: false)
        case .requiresApproval:
            return LoginItemControl(isOn: false, caption: approvalCaption, offersSystemSettings: true)
        case .notFound:
            return LoginItemControl(
                isOn: false,
                caption: shown(registrationError) ?? missingCaption,
                offersSystemSettings: false
            )
        }
    }

    private static func shown(_ registrationError: String?) -> String? {
        guard let registrationError, !registrationError.isEmpty else { return nil }
        return registrationError
    }
}
