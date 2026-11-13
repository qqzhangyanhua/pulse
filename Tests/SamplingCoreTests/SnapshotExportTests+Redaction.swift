import Foundation
import XCTest
@testable import SamplingCore

extension SnapshotExportTests {
    func testDefaultRedactionHidesProcessNameUsernamePathHostnameAndIP() throws {
        let name = "MailHelper"
        let path = "/Users/alice/Applications/Mail.app/Contents/MacOS/Mail"
        let host = "alices-mac.local"
        let ip = "203.0.113.9"
        let frozen = try XCTUnwrap(freeze(
            rows: [row(pid: 11, name: name, memory: 12, path: path, bundle: nil)],
            hostname: host,
            ipAddress: ip
        ))
        XCTAssertEqual(frozen.processes.first?.name, name)
        XCTAssertEqual(frozen.processes.first?.executablePath, path)
        XCTAssertEqual(frozen.hostname, host)
        XCTAssertEqual(frozen.ipAddress, ip)

        let doc = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone).document
        let hidden = "已隐去：进程名、带用户名的路径、主机名、IP"
        for secret in [name, path, "alice", host, ip] {
            XCTAssertFalse(doc.previewText.contains(secret), secret)
            XCTAssertFalse(doc.html.contains(secret), secret)
            XCTAssertFalse(doc.markdown.contains(secret), secret)
        }
        XCTAssertTrue(doc.previewText.contains("已隐藏"))
        XCTAssertTrue(doc.html.contains("已隐藏"))
        XCTAssertTrue(doc.markdown.contains("已隐藏"))
        XCTAssertTrue(doc.previewText.contains(hidden))
        XCTAssertTrue(doc.html.contains(hidden))
        XCTAssertTrue(doc.markdown.contains(hidden))
        XCTAssertEqual(frozen.processes.first?.name, name)
        let lines = doc.previewText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.first, "Pulse 采样")
        XCTAssertEqual(lines.dropFirst().first, hidden)
        XCTAssertTrue(doc.markdown.hasPrefix("# Pulse 采样\n\n\(hidden)"))
        let processLine = "11 · 已隐藏 · 12 字节 · 内存占用 · 不可用 · 1"
        XCTAssertTrue(doc.previewText.contains(processLine))
        XCTAssertTrue(doc.markdown.contains(processLine))
        XCTAssertTrue(doc.html.contains("<td>11</td><td>已隐藏</td><td>12 字节</td><td>内存占用</td><td>不可用</td><td>1</td>"))
        for line in lines.dropFirst() where line != processLine {
            XCTAssertTrue(doc.markdown.contains(line), line)
            XCTAssertTrue(doc.html.contains(line), line)
        }
    }

    func testEachRedactionCategoryCanBeTurnedOffOnItsOwn() throws {
        let name = "MailHelper"
        let path = "/Users/alice/Applications/Mail.app/Contents/MacOS/Mail"
        let host = "alices-mac.local"
        let ip = "203.0.113.9"
        let frozen = try XCTUnwrap(freeze(
            rows: [row(pid: 11, name: name, memory: 12, path: path, bundle: nil)],
            hostname: host,
            ipAddress: ip
        ))
        let process = "11 · 已隐藏 · 12 字节 · 内存占用 · 不可用 · 1"
        let named = "11 · MailHelper · 12 字节 · 内存占用 · 不可用 · 1"
        let withPath = process + " · " + path

        let namesShown = document(frozen, redaction: redaction(processName: false))
        assertSharedRender(namesShown, line: named, disclosure: "已隐去：带用户名的路径、主机名、IP")
        XCTAssertTrue(namesShown.html.contains("<td>MailHelper</td>"))
        for secret in [path, "alice", host, ip] {
            assertAbsent(secret, from: namesShown)
        }
        XCTAssertEqual(frozen.processes.first?.name, name)

        let pathsShown = document(frozen, redaction: redaction(usernamePath: false))
        assertSharedRender(pathsShown, line: withPath, disclosure: "已隐去：进程名、主机名、IP")
        XCTAssertTrue(pathsShown.html.contains("<td>/Users/alice/Applications/Mail.app/Contents/MacOS/Mail</td>"))
        assertAbsent(name, from: pathsShown)
        assertAbsent(host, from: pathsShown)
        assertAbsent(ip, from: pathsShown)

        let hostShown = document(frozen, redaction: redaction(hostname: false))
        assertSharedRender(hostShown, line: process, disclosure: "已隐去：进程名、带用户名的路径、IP")
        XCTAssertTrue(hostShown.previewText.contains("主机名：alices-mac.local"))
        XCTAssertTrue(hostShown.html.contains("主机名：alices-mac.local"))
        XCTAssertTrue(hostShown.markdown.contains("主机名：alices-mac.local"))
        assertAbsent(path, from: hostShown)
        assertAbsent(ip, from: hostShown)
        assertAbsent(name, from: hostShown)

        let addressShown = document(frozen, redaction: redaction(ipAddress: false))
        assertSharedRender(addressShown, line: process, disclosure: "已隐去：进程名、带用户名的路径、主机名")
        XCTAssertTrue(addressShown.previewText.contains("IP：203.0.113.9"))
        XCTAssertTrue(addressShown.html.contains("IP：203.0.113.9"))
        XCTAssertTrue(addressShown.markdown.contains("IP：203.0.113.9"))
        assertAbsent(path, from: addressShown)
        assertAbsent(host, from: addressShown)
        assertAbsent(name, from: addressShown)

        let shown = document(frozen, redaction: redaction(
            processName: false,
            usernamePath: false,
            hostname: false,
            ipAddress: false
        ))
        let revealed = named + " · " + path
        XCTAssertFalse(shown.previewText.contains("已隐去"))
        XCTAssertFalse(shown.html.contains("已隐去"))
        XCTAssertFalse(shown.markdown.contains("已隐去"))
        XCTAssertTrue(shown.previewText.contains(revealed))
        XCTAssertTrue(shown.markdown.contains(revealed))
        XCTAssertTrue(shown.html.contains("<td>MailHelper</td>"))
        XCTAssertTrue(shown.html.contains("<td>\(path)</td>"))
        XCTAssertTrue(shown.previewText.contains("主机名：alices-mac.local"))
        XCTAssertTrue(shown.markdown.contains("IP：203.0.113.9"))
        XCTAssertTrue(shown.html.contains("IP：203.0.113.9"))

        var session = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        XCTAssertTrue(session.hideNames)
        XCTAssertTrue(session.redaction.hidesUsernamePath)
        XCTAssertTrue(session.redaction.hidesHostname)
        XCTAssertTrue(session.redaction.hidesIPAddress)
        session.setHideNames(false)
        session.setHidesUsernamePath(false)
        session.setHidesHostname(false)
        session.setHidesIPAddress(false)
        XCTAssertEqual(session.document.previewText, shown.previewText)
        XCTAssertEqual(session.document.html, shown.html)
        XCTAssertEqual(session.document.markdown, shown.markdown)
        XCTAssertEqual(session.frozen.processes.first?.name, name)
        XCTAssertEqual(session.frozen.hostname, host)
        XCTAssertEqual(session.frozen.ipAddress, ip)
    }

    func testPathsWithoutAUsernameStayOutEvenWhenThatCategoryIsOff() throws {
        let system = "/usr/libexec/syspolicyd"
        let shared = "/Users/Shared/Library/tool"
        let home = "/home/alice/bin/tool"
        let frozen = try XCTUnwrap(freeze(rows: [
            row(pid: 1, name: "syspolicyd", memory: 30, path: system, bundle: nil),
            row(pid: 2, name: "sharedtool", memory: 20, path: shared, bundle: nil),
            row(pid: 3, name: "hometool", memory: 10, path: home, bundle: nil),
        ]))
        let shown = document(frozen, redaction: redaction(
            processName: false,
            usernamePath: false,
            hostname: false,
            ipAddress: false
        ))
        XCTAssertTrue(shown.previewText.contains("syspolicyd"))
        XCTAssertTrue(shown.previewText.contains("sharedtool"))
        XCTAssertTrue(shown.previewText.contains("hometool"))
        XCTAssertTrue(shown.previewText.contains(home))
        XCTAssertTrue(shown.html.contains(home))
        XCTAssertTrue(shown.markdown.contains(home))
        assertAbsent(system, from: shown)
        assertAbsent(shared, from: shown)
        assertAbsent("/Users/Shared", from: shown)
        XCTAssertFalse(shown.previewText.contains("已隐去"))
        XCTAssertFalse(shown.html.contains("已隐去"))
        XCTAssertFalse(shown.markdown.contains("已隐去"))
    }

    func testUsernamePathOutsideTheTopFiveIsNotDisclosed() throws {
        var rows: [ProcessRow] = []
        for index in 1...5 {
            rows.append(row(
                pid: Int32(index),
                name: "Top\(index)",
                memory: UInt64(100 - index),
                path: "/usr/bin/top\(index)",
                bundle: nil
            ))
        }
        rows.append(row(pid: 9, name: "HiddenHome", memory: 1, path: "/Users/carol/secret", bundle: nil))
        let frozen = try XCTUnwrap(freeze(rows: rows))
        let doc = document(frozen, redaction: .default)
        assertAbsent("carol", from: doc)
        assertAbsent("HiddenHome", from: doc)
        assertAbsent("/Users/carol/secret", from: doc)
        XCTAssertTrue(doc.previewText.contains("已隐去：进程名"))
        XCTAssertFalse(doc.previewText.contains("带用户名的路径"))
        XCTAssertTrue(doc.html.contains("已隐去：进程名"))
        XCTAssertTrue(doc.markdown.contains("已隐去：进程名"))
    }

    func testBlankHostnameAndAddressAreNotDisclosed() throws {
        let frozen = try XCTUnwrap(freeze(
            rows: [row(pid: 4, name: "Plain", memory: 8, path: "/usr/bin/plain", bundle: nil)],
            hostname: "   ",
            ipAddress: "\n"
        ))
        XCTAssertNil(frozen.hostname)
        XCTAssertNil(frozen.ipAddress)
        let doc = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone).document
        XCTAssertTrue(doc.previewText.contains("已隐去：进程名"))
        XCTAssertFalse(doc.previewText.contains("主机名"))
        XCTAssertFalse(doc.previewText.contains("IP"))
        XCTAssertFalse(doc.html.contains("主机名"))
        XCTAssertFalse(doc.markdown.contains("IP："))
    }

    func testRevealedUsernamePathIsEscapedInHTMLAndRawInMarkdown() throws {
        let path = "/Users/alice/a<b>&c"
        let frozen = try XCTUnwrap(freeze(rows: [row(pid: 8, name: "Tool", memory: 9, path: path, bundle: nil)]))
        let doc = document(frozen, redaction: redaction(usernamePath: false))
        XCTAssertTrue(doc.previewText.contains(path))
        XCTAssertTrue(doc.markdown.contains(path))
        XCTAssertTrue(doc.html.contains("/Users/alice/a&lt;b&gt;&amp;c"))
        XCTAssertFalse(doc.html.contains("a<b>"))
        XCTAssertFalse(doc.html.contains("Tool"))
    }

    func testHiddenNamesStayOutOfPreviewHTMLAndFilename() throws {
        let sentinel = "Name<script>alert(\"x\")'https://pulse.example/\u{0}Z\u{2028}\u{2029}"
        let frozen = try XCTUnwrap(freeze(rows: [row(pid: 11, name: sentinel, memory: 12, path: nil, bundle: nil)]))
        XCTAssertEqual(frozen.processes.first?.name, sentinel)
        var session = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        session.setHideNames(true)
        let hidden = session.document
        XCTAssertFalse(hidden.previewText.contains(sentinel))
        XCTAssertFalse(hidden.previewText.contains("Name<script"))
        XCTAssertFalse(hidden.previewText.contains("pulse.example"))
        XCTAssertFalse(hidden.html.contains(sentinel))
        XCTAssertFalse(hidden.html.contains("Name"))
        XCTAssertFalse(hidden.html.contains("pulse.example"))
        XCTAssertFalse(hidden.html.contains("<script"))
        XCTAssertFalse(hidden.suggestedFilename.contains("Name"))
        XCTAssertFalse(hidden.suggestedFilename.contains("pulse.example"))
        XCTAssertTrue(hidden.previewText.contains("已隐藏"))
        XCTAssertTrue(hidden.html.contains("已隐藏"))
        XCTAssertEqual(session.frozen.processes.first?.name, sentinel)
        XCTAssertEqual(hidden.suggestedFilename, "Pulse-快照-20010203-040506.html")

        session.setHideNames(false)
        let shown = session.document
        XCTAssertTrue(shown.previewText.contains(sentinel))
        XCTAssertEqual(shown.suggestedFilename, hidden.suggestedFilename)
        XCTAssertTrue(shown.previewText.contains("采样时间：1999-08-07 06:05:04"))
        XCTAssertTrue(shown.previewText.contains("快照生成时间：2001-02-03 04:05:06"))
        XCTAssertEqual(session.frozen.savedAt, savedAt)
    }

    func testVisibleSentinelIsEscapedInHTML() throws {
        let sentinel = "Name<script>alert(\"x\")'https://pulse.example/\u{0}Z\u{2028}\u{2029}"
        let frozen = try XCTUnwrap(freeze(rows: [row(pid: 11, name: sentinel, memory: 12, path: nil, bundle: nil)]))
        let doc = document(frozen, hideNames: false)
        let escaped = "Name&lt;script&gt;alert(&quot;x&quot;)&#39;https://pulse.example/&#0;Z&#8232;&#8233;"
        XCTAssertTrue(doc.previewText.contains(sentinel))
        XCTAssertTrue(doc.html.contains(escaped))
        XCTAssertFalse(doc.html.contains("<script"))
        XCTAssertFalse(doc.html.contains("alert(\"x\")"))
        XCTAssertFalse(doc.html.contains("href"))
        XCTAssertFalse(doc.html.contains("src="))
        XCTAssertFalse(doc.html.contains("javascript:"))
        XCTAssertFalse(doc.html.contains("data:"))
        XCTAssertNil(doc.html.range(of: #"\son[a-zA-Z]+="#, options: .regularExpression))
        XCTAssertFalse(doc.html.unicodeScalars.contains { $0.value == 0 || $0.value == 0x2028 || $0.value == 0x2029 })
        XCTAssertTrue(doc.html.contains("<title>Pulse 采样</title>"))
        XCTAssertFalse(doc.html.contains(sentinel))
    }

    private func redaction(
        processName: Bool = true,
        usernamePath: Bool = true,
        hostname: Bool = true,
        ipAddress: Bool = true
    ) -> SnapshotRedaction {
        SnapshotRedaction(
            hidesProcessName: processName,
            hidesUsernamePath: usernamePath,
            hidesHostname: hostname,
            hidesIPAddress: ipAddress
        )
    }
}
