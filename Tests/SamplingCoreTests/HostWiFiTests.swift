import XCTest
@testable import SamplingCore

/// Portable Wi-Fi reading. RSSI 0 is missing, not a real 0 dBm signal.
final class HostWiFiTests: XCTestCase {
    func testZeroRSSIIsNilNotZero() {
        let reading = HostWiFi.reading(hasInterface: true, rssi: 0, noise: -90)
        XCTAssertNotNil(reading)
        XCTAssertNil(reading?.rssi)
        XCTAssertNotEqual(reading?.rssi, 0)
    }

    func testNoInterfaceIsNilReading() {
        XCTAssertNil(HostWiFi.reading(hasInterface: false, rssi: -55, noise: -90))
    }

    func testNegativeRSSIIsPreserved() {
        let reading = HostWiFi.reading(hasInterface: true, rssi: -55, noise: -90)
        XCTAssertEqual(reading?.rssi, -55)
        XCTAssertEqual(reading?.noise, -90)
        XCTAssertNil(reading?.ssid)
    }

    func testProvidedSSIDIsKeptAndAMissingInterfaceDropsIt() {
        let reading = HostWiFi.reading(hasInterface: true, rssi: -55, noise: -90, ssid: "Cafe Wi-Fi")
        XCTAssertEqual(reading?.ssid, "Cafe Wi-Fi")
        XCTAssertEqual(reading?.rssi, -55)
        let zero = HostWiFi.reading(hasInterface: true, rssi: 0, noise: -90, ssid: "Cafe Wi-Fi")
        XCTAssertNil(zero?.rssi)
        XCTAssertEqual(zero?.ssid, "Cafe Wi-Fi")
        XCTAssertNil(HostWiFi.reading(hasInterface: false, rssi: -55, noise: -90, ssid: "Cafe Wi-Fi"))
    }
}
