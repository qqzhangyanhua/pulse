import XCTest
@testable import SamplingCore

/// Libproc socket facts decoded to sidebar lines. Forged inputs only.
/// No `proc_pidinfo`, no live pid, no `netstat`.
final class ProcessSocketTests: XCTestCase {
    func testTCPListenShowsProtocolAndPort() {
        let lines = ProcessSocketDecoder.lines(from: [tcpListen(port: 3000)])
        XCTAssertEqual(lines.listening, ["TCP 3000"])
        XCTAssertEqual(lines.connections, [])
        XCTAssertFalse(lines.unreadable)
    }

    func testTCPKindWithoutProtocolNumberStillListens() {
        var fact = tcpListen(port: 3000)
        fact.ipProtocol = 0
        let lines = ProcessSocketDecoder.lines(from: [fact])
        XCTAssertEqual(lines.listening, ["TCP 3000"])
        XCTAssertEqual(lines.connections, [])
    }

    func testTCPConnectedShowsRemoteAddressAndPort() {
        let lines = ProcessSocketDecoder.lines(from: [tcpConnected(
            address: "93.184.216.34",
            port: 443
        )])
        XCTAssertEqual(lines.connections, ["TCP 93.184.216.34:443"])
        XCTAssertEqual(lines.listening, [])
        XCTAssertFalse(lines.unreadable)
    }

    func testIPv6ConnectionBracketsTheAddress() {
        let lines = ProcessSocketDecoder.lines(from: [tcpConnected(
            address: "2001:db8::1",
            port: 443,
            family: 30
        )])
        XCTAssertEqual(lines.connections, ["TCP [2001:db8::1]:443"])
        XCTAssertEqual(lines.listening, [])
    }

    func testUnspecifiedPeerIsNotAConnection() {
        let lines = ProcessSocketDecoder.lines(from: [
            tcpConnected(address: "0.0.0.0", port: 80),
            tcpConnected(address: "::", port: 80, family: 30),
        ])
        XCTAssertEqual(lines.connections, [])
        XCTAssertEqual(lines.listening, [])
        XCTAssertFalse(lines.unreadable)
    }

    func testUDPBoundPortIsAListener() {
        let lines = ProcessSocketDecoder.lines(from: [udpBound(port: 5353)])
        XCTAssertEqual(lines.listening, ["UDP 5353"])
        XCTAssertEqual(lines.connections, [])
        XCTAssertFalse(lines.unreadable)
    }

    func testConnectedUDPShowsTheRemoteAndNotTheLocalPort() {
        var fact = udpBound(port: 53000)
        fact.remotePort = 53
        fact.remoteAddress = "8.8.8.8"
        let lines = ProcessSocketDecoder.lines(from: [fact])
        XCTAssertEqual(lines.connections, ["UDP 8.8.8.8:53"])
        XCTAssertEqual(lines.listening, [])
    }

    func testUnreadableSocketIsNotAnEmptySuccess() {
        let lines = ProcessSocketDecoder.lines(from: [.unreadable])
        XCTAssertTrue(lines.unreadable)
        XCTAssertEqual(lines.listening, [])
        XCTAssertEqual(lines.connections, [])
    }

    func testReadableSocketBesideAnUnreadableOneKeepsThePort() {
        let lines = ProcessSocketDecoder.lines(from: [tcpListen(port: 3000), .unreadable])
        XCTAssertEqual(lines.listening, ["TCP 3000"])
        XCTAssertTrue(lines.unreadable)
    }

    func testUnixSocketIsIgnored() {
        let unix = ProcessSocketFact(
            family: 1,
            socketType: 1,
            ipProtocol: 0,
            kind: 3,
            tcpState: nil,
            localPort: nil,
            remotePort: nil,
            remoteAddress: nil,
            readable: true
        )
        let lines = ProcessSocketDecoder.lines(from: [unix])
        XCTAssertEqual(lines.listening, [])
        XCTAssertEqual(lines.connections, [])
        XCTAssertFalse(lines.unreadable)
    }

    func testListeningPortsKeepInputOrder() {
        let lines = ProcessSocketDecoder.lines(from: [tcpListen(port: 8080), tcpListen(port: 3000)])
        XCTAssertEqual(lines.listening, ["TCP 8080", "TCP 3000"])
    }

    func testOwnUserShowsThePortAndAnExplicitEmptyConnection() {
        let text = ProcessSocketPresentation.text(
            rowUid: 501,
            selfUid: 501,
            facts: [tcpListen(port: 3000)]
        )
        XCTAssertEqual(text.listening, "TCP 3000")
        XCTAssertEqual(text.connections, "没有")
        XCTAssertNil(text.permissionNote)
    }

    func testSeveralListenersJoinOnSeparateLines() {
        let text = ProcessSocketPresentation.text(
            rowUid: 501,
            selfUid: 501,
            facts: [tcpListen(port: 3000), udpBound(port: 5353)]
        )
        XCTAssertEqual(text.listening, "TCP 3000\nUDP 5353")
        XCTAssertNil(text.permissionNote)
    }

    func testOwnUserWithNoSocketsSaysNone() {
        let text = ProcessSocketPresentation.text(rowUid: 501, selfUid: 501, facts: [])
        XCTAssertEqual(text.listening, "没有")
        XCTAssertEqual(text.connections, "没有")
        XCTAssertNil(text.permissionNote)
    }

    func testOwnRootProcessIsNotDenied() {
        let text = ProcessSocketPresentation.text(
            rowUid: 0,
            selfUid: 0,
            facts: [tcpListen(port: 3000)]
        )
        XCTAssertEqual(text.listening, "TCP 3000")
        XCTAssertNil(text.permissionNote)
    }

    func testOtherUserShowsDashAndNoPermissionInsteadOfThePorts() {
        let text = ProcessSocketPresentation.text(
            rowUid: 0,
            selfUid: 501,
            facts: [tcpListen(port: 3000)]
        )
        XCTAssertEqual(text.listening, "—")
        XCTAssertEqual(text.connections, "—")
        XCTAssertEqual(text.permissionNote, "没有读取权限")
        XCTAssertFalse(text.listening.contains("3000"))
        XCTAssertFalse(text.connections.contains("3000"))
    }

    func testMissingUidIsDenied() {
        let text = ProcessSocketPresentation.text(rowUid: nil, selfUid: 501, facts: [])
        XCTAssertEqual(text.listening, "—")
        XCTAssertEqual(text.connections, "—")
        XCTAssertEqual(text.permissionNote, "没有读取权限")
    }

    func testUnreadableListStaysMissingWithoutThePermissionNote() {
        let text = ProcessSocketPresentation.text(rowUid: 501, selfUid: 501, facts: nil)
        XCTAssertEqual(text.listening, "—")
        XCTAssertEqual(text.connections, "—")
        XCTAssertNil(text.permissionNote)
    }

    func testOnlyUnreadableSocketsStayMissing() {
        let text = ProcessSocketPresentation.text(rowUid: 501, selfUid: 501, facts: [.unreadable])
        XCTAssertEqual(text.listening, "—")
        XCTAssertEqual(text.connections, "—")
        XCTAssertNil(text.permissionNote)
    }

    private func tcpListen(port: Int) -> ProcessSocketFact {
        ProcessSocketFact(
            family: 2,
            socketType: 1,
            ipProtocol: 6,
            kind: 2,
            tcpState: 1,
            localPort: port,
            remotePort: 0,
            remoteAddress: "0.0.0.0",
            readable: true
        )
    }

    private func tcpConnected(address: String, port: Int, family: Int32 = 2) -> ProcessSocketFact {
        ProcessSocketFact(
            family: family,
            socketType: 1,
            ipProtocol: 6,
            kind: 2,
            tcpState: 4,
            localPort: 49152,
            remotePort: port,
            remoteAddress: address,
            readable: true
        )
    }

    private func udpBound(port: Int) -> ProcessSocketFact {
        ProcessSocketFact(
            family: 2,
            socketType: 2,
            ipProtocol: 17,
            kind: 1,
            tcpState: nil,
            localPort: port,
            remotePort: 0,
            remoteAddress: nil,
            readable: true
        )
    }
}
