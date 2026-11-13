import XCTest
@testable import SamplingCore

/// Path facts in, one connection status and one primary interface out.
final class HostConnectionTests: XCTestCase {
    func testSatisfiedWiFiKeepsTheFirstInterface() {
        let connection = HostConnection.project(
            status: .satisfied,
            interfaces: [.wifi, .wiredEthernet]
        )
        XCTAssertEqual(connection.status, .connected)
        XCTAssertEqual(connection.interface, .wifi)
    }

    func testSatisfiedEthernetKeepsTheFirstInterface() {
        let connection = HostConnection.project(
            status: .satisfied,
            interfaces: [.wiredEthernet, .wifi]
        )
        XCTAssertEqual(connection.status, .connected)
        XCTAssertEqual(connection.interface, .ethernet)
    }

    func testSatisfiedOtherInterfaceStaysOther() {
        let connection = HostConnection.project(
            status: .satisfied,
            interfaces: [.other, .wifi]
        )
        XCTAssertEqual(connection.status, .connected)
        XCTAssertEqual(connection.interface, .other)
    }

    func testUnsatisfiedDropsInterfaces() {
        let connection = HostConnection.project(
            status: .unsatisfied,
            interfaces: [.wifi, .wiredEthernet]
        )
        XCTAssertEqual(connection.status, .disconnected)
        XCTAssertEqual(connection.interface, .none)
    }

    func testRequiresConnectionCanStillBeWiFi() {
        let connection = HostConnection.project(
            status: .requiresConnection,
            interfaces: [.wifi]
        )
        XCTAssertEqual(connection.status, .requiresConnection)
        XCTAssertEqual(connection.interface, .wifi)
    }

    func testSatisfiedWithNoInterfacesIsOtherNotDisconnected() {
        let connection = HostConnection.project(
            status: .satisfied,
            interfaces: []
        )
        XCTAssertEqual(connection.status, .connected)
        XCTAssertEqual(connection.interface, .other)
    }
}
