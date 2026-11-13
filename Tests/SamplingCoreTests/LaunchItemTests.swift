import XCTest
@testable import SamplingCore

/// Plist rows for the machine-page 启动项 list. Forged plists only.
final class LaunchItemTests: XCTestCase {
    func testPlistDecoderKeepsLabelAndProgram() {
        let row = LaunchItemPlistDecoder.row(fileName: "com.example.agent.plist", data: plist("""
        <key>Label</key>
        <string>com.example.agent</string>
        <key>Program</key>
        <string>/usr/local/bin/example</string>
        """))
        XCTAssertEqual(row, LaunchItemRow(
            id: "com.example.agent.plist",
            label: "com.example.agent",
            programPath: "/usr/local/bin/example",
            source: "—",
            signature: "—",
            enabled: "—"
        ))
    }

    func testMissingLabelStaysMissing() {
        let row = LaunchItemPlistDecoder.row(fileName: "agent.plist", data: plist("""
        <key>Program</key>
        <string>/usr/local/bin/example</string>
        """))
        XCTAssertEqual(row.label, "—")
        XCTAssertEqual(row.programPath, "/usr/local/bin/example")
    }

    func testBlankLabelStaysMissing() {
        let row = LaunchItemPlistDecoder.row(fileName: "agent.plist", data: plist("""
        <key>Label</key>
        <string>   </string>
        <key>Program</key>
        <string>/usr/local/bin/example</string>
        """))
        XCTAssertEqual(row.label, "—")
        XCTAssertEqual(row.programPath, "/usr/local/bin/example")
    }

    func testMissingProgramUsesTheFirstArgument() {
        let row = LaunchItemPlistDecoder.row(fileName: "agent.plist", data: plist("""
        <key>Label</key>
        <string>com.example.agent</string>
        <key>ProgramArguments</key>
        <array>
        <string>/opt/example</string>
        <string>--flag</string>
        </array>
        """))
        XCTAssertEqual(row.label, "com.example.agent")
        XCTAssertEqual(row.programPath, "/opt/example")
    }

    func testProgramWinsOverProgramArguments() {
        let row = LaunchItemPlistDecoder.row(fileName: "agent.plist", data: plist("""
        <key>Label</key>
        <string>com.example.agent</string>
        <key>Program</key>
        <string>/usr/local/bin/example</string>
        <key>ProgramArguments</key>
        <array>
        <string>/opt/other</string>
        </array>
        """))
        XCTAssertEqual(row.programPath, "/usr/local/bin/example")
    }

    func testMissingProgramAndArgumentsStayMissing() {
        let row = LaunchItemPlistDecoder.row(fileName: "agent.plist", data: plist("""
        <key>Label</key>
        <string>com.example.agent</string>
        """))
        XCTAssertEqual(row.label, "com.example.agent")
        XCTAssertEqual(row.programPath, "—")
    }

    func testBadPlistStaysMissingInsteadOfCrashing() {
        let garbage = LaunchItemPlistDecoder.row(fileName: "broken.plist", data: Data("not a plist".utf8))
        XCTAssertEqual(garbage, LaunchItemRow(
            id: "broken.plist",
            label: "—",
            programPath: "—",
            source: "—",
            signature: "—",
            enabled: "—"
        ))
        let array = LaunchItemPlistDecoder.row(fileName: "array.plist", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <array><string>nope</string></array>
        </plist>
        """.utf8))
        XCTAssertEqual(array.label, "—")
        XCTAssertEqual(array.programPath, "—")
    }

    func testRowShowsSourceSignatureAndEnabledState() {
        let rows = LaunchItemList.rows(from: [
            LaunchItemDirectoryRead(
                source: "用户 LaunchAgents",
                files: [
                    LaunchItemFile(
                        fileName: "com.example.agent.plist",
                        data: plist("""
                        <key>Label</key>
                        <string>com.example.agent</string>
                        <key>Program</key>
                        <string>/usr/local/bin/example</string>
                        """),
                        status: .enabled,
                        signature: ProcessSigningFacts(
                            status: 0,
                            teamIdentifier: nil,
                            certificateSummaries: [
                                "Software Signing",
                                "Apple Code Signing Certification Authority",
                            ],
                            flags: 0
                        )
                    ),
                ]
            ),
        ])
        XCTAssertEqual(rows, [
            LaunchItemRow(
                id: "用户 LaunchAgents|com.example.agent.plist",
                label: "com.example.agent",
                programPath: "/usr/local/bin/example",
                source: "用户 LaunchAgents",
                signature: "Apple",
                enabled: "已启用"
            ),
        ])
    }

    func testSignatureReusesTheProcessDecoder() {
        let developer = row(status: .enabled, facts: ProcessSigningFacts(
            status: 0,
            teamIdentifier: "ABCDE12345",
            certificateSummaries: ["Developer ID Application: Northwind (ABCDE12345)"],
            flags: 0
        ))
        XCTAssertEqual(developer.signature, "开发者：Northwind")

        let unsigned = row(status: .enabled, facts: ProcessSigningFacts(
            status: -67062,
            teamIdentifier: "ABCDE12345",
            certificateSummaries: ["Developer ID Application: Northwind (ABCDE12345)"],
            flags: 0
        ))
        XCTAssertEqual(unsigned.signature, "未签名")

        let missing = row(status: .enabled, facts: nil)
        XCTAssertEqual(missing.signature, "—")
    }

    func testKnownStatusesUseCalmCopyAndUnreadableStatusStaysMissing() {
        XCTAssertEqual(row(status: .notRegistered, facts: nil).enabled, "未启用")
        XCTAssertEqual(row(status: .requiresApproval, facts: nil).enabled, "需要批准")
        XCTAssertEqual(row(status: .notFound, facts: nil).enabled, "—")
        XCTAssertEqual(row(status: nil, facts: nil).enabled, "—")
    }

    func testUnreadableDirectoryShowsAMissingRow() {
        let rows = LaunchItemList.rows(from: [
            LaunchItemDirectoryRead(source: "本机 LaunchDaemons", files: nil),
        ])
        XCTAssertEqual(rows, [
            LaunchItemRow(
                id: "unreadable-0",
                label: "—",
                programPath: "—",
                source: "—",
                signature: "—",
                enabled: "—"
            ),
        ])
    }

    func testReadableEmptyDirectoryAddsNoRow() {
        XCTAssertEqual(
            LaunchItemList.rows(from: [
                LaunchItemDirectoryRead(source: "用户 LaunchAgents", files: []),
            ]),
            []
        )
    }

    func testMissingProgramDoesNotBorrowASignature() {
        let rows = LaunchItemList.rows(from: [
            LaunchItemDirectoryRead(
                source: "本机 LaunchAgents",
                files: [
                    LaunchItemFile(
                        fileName: "no-program.plist",
                        data: plist("""
                        <key>Label</key>
                        <string>com.example.no-program</string>
                        """),
                        status: .enabled,
                        signature: ProcessSigningFacts(
                            status: 0,
                            teamIdentifier: nil,
                            certificateSummaries: ["Software Signing"],
                            flags: 0
                        )
                    ),
                ]
            ),
        ])
        XCTAssertEqual(rows.first?.label, "com.example.no-program")
        XCTAssertEqual(rows.first?.programPath, "—")
        XCTAssertEqual(rows.first?.signature, "—")
        XCTAssertEqual(rows.first?.enabled, "已启用")
        XCTAssertEqual(rows.first?.source, "本机 LaunchAgents")
    }

    func testDisabledKeyDoesNotReplaceTheStatus() {
        let rows = LaunchItemList.rows(from: [
            LaunchItemDirectoryRead(
                source: "用户 LaunchAgents",
                files: [
                    LaunchItemFile(
                        fileName: "disabled.plist",
                        data: plist("""
                        <key>Label</key>
                        <string>com.example.disabled</string>
                        <key>Program</key>
                        <string>/usr/local/bin/example</string>
                        <key>Disabled</key>
                        <true/>
                        """),
                        status: .enabled,
                        signature: nil
                    ),
                ]
            ),
        ])
        XCTAssertEqual(rows.first?.enabled, "已启用")
        XCTAssertEqual(rows.first?.label, "com.example.disabled")
    }

    func testMachinePageStartsTheLaunchItemWatchAndKeepsTheRows() {
        var core = DashboardCore(ownPid: 1)
        XCTAssertEqual(core.launchItems, [])
        let entered = core.selectPage(.machine)
        XCTAssertTrue(entered.contains(.startLaunchItemWatch))
        XCTAssertFalse(entered.contains(.stopLaunchItemWatch))

        let row = LaunchItemRow(
            id: "用户 LaunchAgents|com.example.agent.plist",
            label: "com.example.agent",
            programPath: "/usr/local/bin/example",
            source: "用户 LaunchAgents",
            signature: "Apple",
            enabled: "已启用"
        )
        XCTAssertEqual(core.apply(launchItems: [row]), [])
        XCTAssertEqual(core.launchItems, [row])

        let left = core.selectPage(.cpu)
        XCTAssertTrue(left.contains(.stopLaunchItemWatch))
        XCTAssertFalse(left.contains(.startLaunchItemWatch))
        XCTAssertEqual(core.launchItems, [row])
    }

    private func row(status: LaunchItemStatus?, facts: ProcessSigningFacts?) -> LaunchItemRow {
        let rows = LaunchItemList.rows(from: [
            LaunchItemDirectoryRead(
                source: "用户 LaunchAgents",
                files: [
                    LaunchItemFile(
                        fileName: "com.example.agent.plist",
                        data: plist("""
                        <key>Label</key>
                        <string>com.example.agent</string>
                        <key>Program</key>
                        <string>/usr/local/bin/example</string>
                        """),
                        status: status,
                        signature: facts
                    ),
                ]
            ),
        ])
        return rows[0]
    }

    private func plist(_ body: String) -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>
        """
        return Data(xml.utf8)
    }
}
