import XCTest
@testable import SamplingCore

/// Manual public-IP lookup. The transport is the network boundary; addresses are parsed, not trusted.
final class PublicIPLookupTests: XCTestCase {
    func testPrimarySuccessReturnsTheTrimmedAddress() async {
        let transport = ScriptedPublicIPTransport(results: [
            PublicIPLookup.primaryEndpoint: .success("  203.0.113.8\n"),
        ])

        let result = await PublicIPLookup.lookup(using: transport)

        XCTAssertEqual(try? result.get(), "203.0.113.8")
        XCTAssertEqual(transport.requested, [PublicIPLookup.primaryEndpoint])
    }

    func testPrimaryThrowFallsThroughToTheBackup() async {
        let transport = ScriptedPublicIPTransport(results: [
            PublicIPLookup.primaryEndpoint: .failure(ScriptedPublicIPError.offline),
            PublicIPLookup.fallbackEndpoint: .success("2001:db8::1\n"),
        ])

        let result = await PublicIPLookup.lookup(using: transport)

        XCTAssertEqual(try? result.get(), "2001:db8::1")
        XCTAssertEqual(
            transport.requested,
            [PublicIPLookup.primaryEndpoint, PublicIPLookup.fallbackEndpoint]
        )
    }

    func testPrimaryHTMLFallsThroughToTheBackup() async {
        let transport = ScriptedPublicIPTransport(results: [
            PublicIPLookup.primaryEndpoint: .success("<html><body>Sign in to the network</body></html>"),
            PublicIPLookup.fallbackEndpoint: .success("198.51.100.23"),
        ])

        let result = await PublicIPLookup.lookup(using: transport)

        XCTAssertEqual(try? result.get(), "198.51.100.23")
        XCTAssertEqual(
            transport.requested,
            [PublicIPLookup.primaryEndpoint, PublicIPLookup.fallbackEndpoint]
        )
    }

    func testBothEndpointsThrowingIsFailure() async {
        let transport = ScriptedPublicIPTransport(results: [
            PublicIPLookup.primaryEndpoint: .failure(ScriptedPublicIPError.offline),
            PublicIPLookup.fallbackEndpoint: .failure(ScriptedPublicIPError.offline),
        ])

        let result = await PublicIPLookup.lookup(using: transport)

        guard case .failure = result else {
            XCTFail("expected failure, got \(result)")
            return
        }
        XCTAssertEqual(
            transport.requested,
            [PublicIPLookup.primaryEndpoint, PublicIPLookup.fallbackEndpoint]
        )
    }

    func testBothInvalidBodiesAreFailure() async {
        let transport = ScriptedPublicIPTransport(results: [
            PublicIPLookup.primaryEndpoint: .success("<!DOCTYPE html><html>portal</html>"),
            PublicIPLookup.fallbackEndpoint: .success("not an address"),
        ])

        let result = await PublicIPLookup.lookup(using: transport)

        guard case .failure = result else {
            XCTFail("expected failure, got \(result)")
            return
        }
    }

    func testIPv4AndIPv6AreAccepted() {
        XCTAssertEqual(PublicIPAddress.parse("203.0.113.8"), "203.0.113.8")
        XCTAssertEqual(PublicIPAddress.parse("255.255.255.255"), "255.255.255.255")
        XCTAssertEqual(PublicIPAddress.parse("0.0.0.0"), "0.0.0.0")
        XCTAssertEqual(PublicIPAddress.parse("2001:db8::1"), "2001:db8::1")
        XCTAssertEqual(PublicIPAddress.parse("2001:DB8:0000:0000:0000:0000:0000:0001"), "2001:DB8:0000:0000:0000:0000:0000:0001")
        XCTAssertEqual(PublicIPAddress.parse("::1"), "::1")
        XCTAssertEqual(PublicIPAddress.parse("::ffff:192.0.2.1"), "::ffff:192.0.2.1")
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(PublicIPAddress.parse(" \t203.0.113.8\r\n"), "203.0.113.8")
        XCTAssertEqual(PublicIPAddress.parse("\n2001:db8::1  "), "2001:db8::1")
    }

    func testHTMLAndOtherBodiesAreRejected() {
        XCTAssertNil(PublicIPAddress.parse("<html>203.0.113.8</html>"))
        XCTAssertNil(PublicIPAddress.parse("<!DOCTYPE html>"))
        XCTAssertNil(PublicIPAddress.parse("203.0.113.8 extra"))
        XCTAssertNil(PublicIPAddress.parse("not an address"))
        XCTAssertNil(PublicIPAddress.parse("256.1.1.1"))
        XCTAssertNil(PublicIPAddress.parse("1.2.3"))
        XCTAssertNil(PublicIPAddress.parse(""))
        XCTAssertNil(PublicIPAddress.parse("   "))
        XCTAssertNil(PublicIPAddress.parse("1::2::3"))
    }
}

private struct ScriptedPublicIPError: Error {
    static let offline = ScriptedPublicIPError()
}

private final class ScriptedPublicIPTransport: PublicIPTransport {
    let results: [URL: Result<String, Error>]
    private(set) var requested: [URL] = []

    init(results: [URL: Result<String, Error>]) {
        self.results = results
    }

    func body(from url: URL) async throws -> String {
        requested.append(url)
        switch results[url] {
        case .success(let body):
            return body
        case .failure(let error):
            throw error
        case nil:
            throw ScriptedPublicIPError.offline
        }
    }
}
