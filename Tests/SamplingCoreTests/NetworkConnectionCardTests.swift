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
    }

    private func connection(status: ConnectionStatus, interface: ConnectionInterface) -> HostConnection {
        HostConnection(status: status, interface: interface)
    }
}
