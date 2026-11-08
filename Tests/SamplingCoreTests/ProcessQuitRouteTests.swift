import XCTest
@testable import SamplingCore

/// Quit routing only. These tests do not send a signal or touch a live pid.
final class ProcessQuitRouteTests: XCTestCase {
    func testApplicationObjectNeverUsesASignal() {
        let paths: [String?] = [
            nil,
            "",
            "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
            "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock",
            "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
            "/usr/sbin/syslogd",
            "/Users/me/Library/Application Support/helper",
        ]
        for path in paths {
            for force in [false, true] {
                let route = ProcessQuitRoute.decide(
                    hasApplication: true,
                    executablePath: path,
                    force: force
                )
                XCTAssertEqual(route, .application, "\(path ?? "nil") force=\(force)")
            }
        }
    }

    func testOrdinaryQuitOfAUserHelperIsSigterm() {
        let paths = [
            "/Users/me/Library/Application Support/Code/coder",
            "/opt/homebrew/bin/node",
            "/usr/bin/ssh",
            "/bin/zsh",
            "/Applications/Foo.app/Contents/Helpers/Foo Helper",
        ]
        for path in paths {
            XCTAssertEqual(
                ProcessQuitRoute.decide(hasApplication: false, executablePath: path, force: false),
                .signal(.sigterm),
                path
            )
        }
    }

    func testForceQuitOfAUserHelperIsSigkill() {
        XCTAssertEqual(
            ProcessQuitRoute.decide(
                hasApplication: false,
                executablePath: "/opt/homebrew/bin/node",
                force: true
            ),
            .signal(.sigkill)
        )
    }

    func testDirectoryPrefixDoesNotRefuseALongerFirstSegment() {
        let paths = [
            "/Systematic/helper",
            "/usr/libexecfoo",
            "/usr/sbinfoo",
            "/sbinfoo",
            "/usr/lib/dyld",
        ]
        for path in paths {
            XCTAssertEqual(
                ProcessQuitRoute.decide(hasApplication: false, executablePath: path, force: false),
                .signal(.sigterm),
                path
            )
            XCTAssertEqual(
                ProcessQuitRoute.decide(hasApplication: false, executablePath: path, force: true),
                .signal(.sigkill),
                path
            )
        }
    }

    func testSystemDirectoryPrefixesAreRefused() {
        let paths = [
            "/System",
            "/System/Library/Frameworks/AppKit.framework/AppKit",
            "/usr/libexec",
            "/usr/libexec/trustd",
            "/usr/sbin",
            "/usr/sbin/syslogd",
            "/sbin",
            "/sbin/launchd",
        ]
        for path in paths {
            for force in [false, true] {
                XCTAssertEqual(
                    ProcessQuitRoute.decide(hasApplication: false, executablePath: path, force: force),
                    .refused,
                    "\(path) force=\(force)"
                )
            }
        }
    }

    func testMissingPathIsRefused() {
        let paths: [String?] = [nil, ""]
        for path in paths {
            for force in [false, true] {
                XCTAssertEqual(
                    ProcessQuitRoute.decide(hasApplication: false, executablePath: path, force: force),
                    .refused,
                    "\(path ?? "nil") force=\(force)"
                )
            }
        }
    }

    func testRefusedProcessThatIsStillAliveIsRequestFailed() {
        XCTAssertEqual(ProcessQuitRoute.refusedResult(isAlive: true), .requestFailed)
    }

    func testRefusedProcessThatIsAlreadyGoneIsNotFound() {
        XCTAssertEqual(ProcessQuitRoute.refusedResult(isAlive: false), .notFound)
    }

    func testSignalFailureMapsESRCHToNotFoundAndAnythingElseToRequestFailed() {
        XCTAssertEqual(ProcessQuitRoute.signalFailure(noSuchProcess: true), .notFound)
        XCTAssertEqual(ProcessQuitRoute.signalFailure(noSuchProcess: false), .requestFailed)
    }
}
