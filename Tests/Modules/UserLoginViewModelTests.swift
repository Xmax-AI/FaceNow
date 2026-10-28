import Foundation
import XCTest
import FNNetwork
@testable import FNUser

@MainActor
final class UserLoginViewModelTests: XCTestCase {

    func testChannelSwitchRestoresIndependentUnmodifiedDrafts() async {
        let model = UserLoginViewModel()
        let initial = model.switchMethod(
            .email,
            account: "13800000000",
            code: "123456"
        )
        XCTAssertEqual(
            initial.account,
            ""
        )
        XCTAssertEqual(
            initial.code,
            ""
        )
        let phone = model.switchMethod(
            .sms,
            account: " User@Example.com ",
            code: "654321"
        )
        XCTAssertEqual(
            phone.account,
            "13800000000"
        )
        XCTAssertEqual(
            phone.code,
            "123456"
        )
        let email = model.switchMethod(
            .email,
            account: "13900000000",
            code: ""
        )
        XCTAssertEqual(
            email.account,
            " User@Example.com "
        )
        XCTAssertEqual(
            email.code,
            "654321"
        )
    }

    func testResendDeadlineIsMonotonicAndScopedToChannelAndDestination() async {
        var now: TimeInterval = 100
        let model = UserLoginViewModel(uptime: { now })
        model.recordCodeSent(
            to: "13800000000",
            method: .sms,
            cooldown: 60
        )
        XCTAssertEqual(
            model.cooldown(for: "13800000000"),
            60
        )
        XCTAssertEqual(
            model.cooldown(for: "13900000000"),
            0
        )
        now = 130.2
        XCTAssertEqual(
            model.cooldown(for: "13800000000"),
            30
        )
        _ = model.switchMethod(
            .email,
            account: "13800000000",
            code: ""
        )
        model.recordCodeSent(
            to: "User@Example.com",
            method: .email,
            cooldown: 45
        )
        XCTAssertEqual(
            model.cooldown(for: " user@example.com "),
            45
        )
        XCTAssertEqual(
            model.cooldown(for: "other@example.com"),
            0
        )
        _ = model.switchMethod(
            .sms,
            account: "",
            code: ""
        )
        XCTAssertEqual(
            model.cooldown(for: "13800000000"),
            30
        )
        now = 161
        XCTAssertEqual(
            model.cooldown(for: "13800000000"),
            0
        )
    }

    func testValidationFollowsTheSelectedPlatformChannelAndPreservesEnteredCase() async {
        let model = UserLoginViewModel()
        XCTAssertTrue(model.isValidAccount(" 13800000000\n"))
        XCTAssertFalse(model.isValidAccount("12800000000"))
        XCTAssertFalse(model.isValidAccount("user@example.com"))
        _ = model.switchMethod(
            .email,
            account: "",
            code: ""
        )
        XCTAssertTrue(model.isValidAccount(" User@Example.com "))
        XCTAssertEqual(
            model.destination(from: " User@Example.com "),
            "User@Example.com"
        )
        XCTAssertFalse(model.isValidAccount("user@example"))
        XCTAssertFalse(
            model.isValidAccount(
                String(
                    repeating: "a",
                    count: 250
                ) + "@example.com"
            )
        )
    }

    func testTenantSettingsControlFilteringWithoutAcceptingNonASCIIDigits() async throws {
        let model = UserLoginViewModel()
        XCTAssertEqual(
            model.codeLength,
            6
        )
        var configuration = LoginConfiguration()
        configuration.tenantName = AccountAPI.tenant
        configuration.smsCodeLength = 4
        configuration.emailCodeLength = 8
        try model.applyConfiguration(configuration)
        XCTAssertEqual(
            model.filteredCode("a1２2٣3-456"),
            "1234"
        )
        _ = model.switchMethod(
            .email,
            account: "",
            code: ""
        )
        XCTAssertEqual(
            model.codeLength,
            8
        )
        XCTAssertEqual(
            model.filteredCode("12 34-567890"),
            "12345678"
        )
    }

    func testWrongTenantCannotReplaceAcceptedLoginSettings() async throws {
        let model = UserLoginViewModel()
        var accepted = LoginConfiguration()
        accepted.tenantName = AccountAPI.tenant
        accepted.smsCodeLength = 4
        try model.applyConfiguration(accepted)
        var rejected = accepted
        rejected.tenantName = "another-tenant"
        rejected.smsCodeLength = 12
        XCTAssertThrowsError(try model.applyConfiguration(rejected))
        XCTAssertEqual(
            model.configuration?.tenantName,
            AccountAPI.tenant
        )
        XCTAssertEqual(
            model.codeLength,
            4
        )
    }
}
