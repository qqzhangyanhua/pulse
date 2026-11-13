import XCTest
@testable import SamplingCore

/// Exact executable-path match from a process to one launch item.
/// Forged rows only. No directory listing.
final class LaunchItemMatchTests: XCTestCase {
    func testExactExecutablePathReturnsThatLaunchItem() {
        let other = LaunchItemRow(
            id: "本机 LaunchDaemons|com.example.other.plist",
            label: "com.example.other",
            programPath: "/usr/local/bin/other",
            source: "本机 LaunchDaemons",
            signature: "未签名",
            enabled: "未启用"
        )
        let matched = LaunchItemRow(
            id: "用户 LaunchAgents|com.example.agent.plist",
            label: "com.example.agent",
            programPath: "/usr/local/bin/example",
            source: "用户 LaunchAgents",
            signature: "Apple",
            enabled: "已启用"
        )
        XCTAssertEqual(
            launchItem(
                forExecutablePath: "/usr/local/bin/example",
                items: [other, matched]
            ),
            matched
        )
    }

    func testNoExactPathReturnsNil() {
        let item = LaunchItemRow(
            id: "用户 LaunchAgents|com.example.agent.plist",
            label: "com.example.agent",
            programPath: "/usr/local/bin/example",
            source: "用户 LaunchAgents",
            signature: "Apple",
            enabled: "已启用"
        )
        XCTAssertNil(launchItem(forExecutablePath: "/usr/local/bin/other", items: [item]))
        XCTAssertNil(launchItem(forExecutablePath: "/usr/local/bin/example/helper", items: [item]))
        XCTAssertNil(launchItem(forExecutablePath: "/usr/local/bin", items: [item]))
        XCTAssertNil(launchItem(forExecutablePath: "/usr/local/bin/Example", items: [item]))
        XCTAssertNil(launchItem(forExecutablePath: "/usr/local/bin/example ", items: [item]))
        XCTAssertNil(launchItem(forExecutablePath: nil, items: [item]))
        XCTAssertNil(launchItem(forExecutablePath: "/usr/local/bin/example", items: []))
    }

    func testMoreThanOneExactPathReturnsNil() {
        let first = LaunchItemRow(
            id: "用户 LaunchAgents|com.example.agent.plist",
            label: "com.example.agent",
            programPath: "/usr/local/bin/example",
            source: "用户 LaunchAgents",
            signature: "Apple",
            enabled: "已启用"
        )
        let second = LaunchItemRow(
            id: "本机 LaunchAgents|com.example.again.plist",
            label: "com.example.again",
            programPath: "/usr/local/bin/example",
            source: "本机 LaunchAgents",
            signature: "开发者：Northwind",
            enabled: "需要批准"
        )
        let other = LaunchItemRow(
            id: "本机 LaunchDaemons|com.example.other.plist",
            label: "com.example.other",
            programPath: "/usr/local/bin/other",
            source: "本机 LaunchDaemons",
            signature: "未签名",
            enabled: "—"
        )
        XCTAssertNil(
            launchItem(
                forExecutablePath: "/usr/local/bin/example",
                items: [first, other, second]
            )
        )
    }

    func testStartedLineNamesThatLaunchItem() {
        XCTAssertEqual(
            LaunchItemCopy.startedLine(label: "com.example.agent"),
            "由 com.example.agent 启动，退出后可能自动重启"
        )
    }
}
