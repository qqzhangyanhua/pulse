import XCTest
@testable import SamplingCore

final class LoginItemTests: XCTestCase {
    func testNotRegisteredStaysOffWithoutACaption() {
        let control = LoginItemProjection.control(status: .notRegistered, registrationError: nil)
        XCTAssertFalse(control.isOn)
        XCTAssertNil(control.caption)
        XCTAssertFalse(control.offersSystemSettings)
    }

    func testEnabledIsOnWithoutACaption() {
        let control = LoginItemProjection.control(status: .enabled, registrationError: nil)
        XCTAssertTrue(control.isOn)
        XCTAssertNil(control.caption)
        XCTAssertFalse(control.offersSystemSettings)
    }

    func testRequiresApprovalStaysOffWithAnExplanationAndSettingsButton() {
        let control = LoginItemProjection.control(status: .requiresApproval, registrationError: "用户尚未允许")
        XCTAssertFalse(control.isOn)
        XCTAssertEqual(control.caption, "需要在系统设置的登录项里允许 Pulse。")
        XCTAssertTrue(control.offersSystemSettings)
        XCTAssertEqual(LoginItemProjection.openSettingsButton, "打开系统设置")
    }

    func testRegisterFailureStaysOffAndShowsTheError() {
        let control = LoginItemProjection.control(status: .notRegistered, registrationError: "无法注册")
        XCTAssertFalse(control.isOn)
        XCTAssertEqual(control.caption, "无法注册")
        XCTAssertFalse(control.offersSystemSettings)
    }

    func testNotFoundStaysOffAndNamesTheMissingItem() {
        let control = LoginItemProjection.control(status: .notFound, registrationError: nil)
        XCTAssertFalse(control.isOn)
        XCTAssertEqual(control.caption, "系统找不到这项登录项。")
        XCTAssertFalse(control.offersSystemSettings)
    }

    func testEnabledStaysOnWhenUnregisterFails() {
        let control = LoginItemProjection.control(status: .enabled, registrationError: "无法关闭")
        XCTAssertTrue(control.isOn)
        XCTAssertEqual(control.caption, "无法关闭")
        XCTAssertFalse(control.offersSystemSettings)
    }

    func testNotFoundPrefersTheRegistrationErrorOverTheMissingLine() {
        let control = LoginItemProjection.control(status: .notFound, registrationError: "无法注册")
        XCTAssertFalse(control.isOn)
        XCTAssertEqual(control.caption, "无法注册")
        XCTAssertFalse(control.offersSystemSettings)
    }

    func testBlankRegistrationErrorDoesNotInventACaption() {
        let control = LoginItemProjection.control(status: .notRegistered, registrationError: "")
        XCTAssertFalse(control.isOn)
        XCTAssertNil(control.caption)
    }
}
