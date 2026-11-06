enum ThermalCondition: Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

enum ThermalNotice {
    static let throttling = "系统正在降频以控制温度"

    static func message(for condition: ThermalCondition) -> String? {
        switch condition {
        case .serious, .critical:
            return throttling
        case .nominal, .fair, .unknown:
            return nil
        }
    }
}
