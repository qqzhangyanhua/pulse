import XCTest
@testable import SamplingCore

/// Status and type rows only. A missing path stays 「—」, never a fake link.
final class NetworkConnectionCardTests: XCTestCase {
    func testConnectedStatusRow() {
        let card = NetworkConnectionCard.project(connection(status: .connected, interface: .wifi))
        XCTAssertEqual(card.status.title, "状态")
        XCTAssertEqual(card.status.value, "已连接")
    }

    func testDisconnectedStatusRow() {
        let card = NetworkConnectionCard.project(connection(status: .disconnected, interface: .none))
        XCTAssertEqual(card.status.title, "状态")
        XCTAssertEqual(card.status.value, "未连接")
    }

    func testRequiresConnectionStatusRow() {
        let card = NetworkConnectionCard.project(connection(status: .requiresConnection, interface: .wifi))
        XCTAssertEqual(card.status.title, "状态")
        XCTAssertEqual(card.status.value, "需要登录或配置")
    }

    func testWiFiTypeRow() {
        let card = NetworkConnectionCard.project(connection(status: .connected, interface: .wifi))
        XCTAssertEqual(card.type.title, "类型")
        XCTAssertEqual(card.type.value, "Wi-Fi")
    }

    func testEthernetTypeRow() {
        let card = NetworkConnectionCard.project(connection(status: .connected, interface: .ethernet))
        XCTAssertEqual(card.type.title, "类型")
        XCTAssertEqual(card.type.value, "以太网")
    }

    func testOtherTypeRow() {
        let card = NetworkConnectionCard.project(connection(status: .connected, interface: .other))
        XCTAssertEqual(card.type.title, "类型")
        XCTAssertEqual(card.type.value, "其它")
    }

    func testNoInterfaceTypeRowSaysDisconnected() {
        let card = NetworkConnectionCard.project(connection(status: .disconnected, interface: .none))
        XCTAssertEqual(card.type.title, "类型")
        XCTAssertEqual(card.type.value, "未连接")
    }

    func testMissingConnectionShowsDashes() {
        let card = NetworkConnectionCard.project(nil)
        XCTAssertEqual(card.status.title, "状态")
        XCTAssertEqual(card.status.value, "—")
        XCTAssertEqual(card.type.title, "类型")
        XCTAssertEqual(card.type.value, "—")
        XCTAssertNotEqual(card.status.value, "未连接")
        XCTAssertNotEqual(card.type.value, "未连接")
        XCTAssertNil(card.signal)
    }

    func testSignalBandBoundaries() {
        XCTAssertEqual(signalValue(-59), "强 (−59 dBm)")
        XCTAssertEqual(signalValue(-60), "强 (−60 dBm)")
        XCTAssertEqual(signalValue(-61), "中 (−61 dBm)")
        XCTAssertEqual(signalValue(-69), "中 (−69 dBm)")
        XCTAssertEqual(signalValue(-70), "中 (−70 dBm)")
        XCTAssertEqual(signalValue(-71), "弱 (−71 dBm)")
        for rssi in [-59, -60, -61, -69, -70, -71] {
            XCTAssertFalse(signalValue(rssi).contains("-"), "RSSI \(rssi) must use U+2212, not a hyphen")
        }
    }

    func testMissingRSSIShowsADashNotZero() {
        let absent = NetworkConnectionCard.project(
            connection(status: .connected, interface: .wifi),
            wifi: nil
        )
        XCTAssertEqual(absent.signal?.title, "信号")
        XCTAssertEqual(absent.signal?.value, "—")
        XCTAssertNotEqual(absent.signal?.value, "0")
        XCTAssertFalse(absent.signal?.value.contains("0") ?? true)

        let zeroed = NetworkConnectionCard.project(
            connection(status: .connected, interface: .wifi),
            wifi: HostWiFiReading(rssi: nil, noise: -90, ssid: nil)
        )
        XCTAssertEqual(zeroed.signal?.value, "—")
    }

    func testWiFiShowsTheSignalRow() {
        let card = NetworkConnectionCard.project(
            connection(status: .connected, interface: .wifi),
            wifi: HostWiFiReading(rssi: -55, noise: -90, ssid: nil)
        )
        XCTAssertEqual(card.signal?.title, "信号")
        XCTAssertEqual(card.signal?.value, "强 (−55 dBm)")
    }

    func testEthernetHidesTheSignalRow() {
        let card = NetworkConnectionCard.project(
            connection(status: .connected, interface: .ethernet),
            wifi: HostWiFiReading(rssi: -55, noise: -90, ssid: nil)
        )
        XCTAssertNil(card.signal)
    }

    func testOtherNoneAndMissingConnectionHideTheSignalRow() {
        let reading = HostWiFiReading(rssi: -55, noise: -90, ssid: nil)
        XCTAssertNil(
            NetworkConnectionCard.project(
                connection(status: .connected, interface: .other),
                wifi: reading
            ).signal
        )
        XCTAssertNil(
            NetworkConnectionCard.project(
                connection(status: .disconnected, interface: .none),
                wifi: reading
            ).signal
        )
        XCTAssertNil(NetworkConnectionCard.project(nil, wifi: reading).signal)
    }

    private func signalValue(_ rssi: Int) -> String {
        let card = NetworkConnectionCard.project(
            connection(status: .connected, interface: .wifi),
            wifi: HostWiFiReading(rssi: rssi, noise: -90, ssid: nil)
        )
        return card.signal?.value ?? ""
    }

    private func connection(status: ConnectionStatus, interface: ConnectionInterface) -> HostConnection {
        HostConnection(status: status, interface: interface)
    }
}
