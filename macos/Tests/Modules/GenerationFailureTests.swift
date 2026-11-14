import XCTest
@testable import FNGenerationModels

final class GenerationFailureTests: XCTestCase {

    func testKnownCreditCodesDoNotDependOnServerWording() {
        for code in [43001, 46017] {
            XCTAssertTrue(GenerationFailure.isInsufficientCredits(apiCode: code, message: "Billing refused"))
        }
    }

    func testLegacyCreditMessagesAndSessionCloseReasonsAreRecognized() {
        for message in [
            "积分不足，请先充值", "账户余额不足", "积分已用完", "积分已耗尽",
            "INSUFFICIENT_CREDITS", "insufficient_points", "Not enough credits",
            "Your balance is insufficient", "Out of credits", "No credits remaining",
            "Credits exhausted", "Your credits have run out",
        ] {
            XCTAssertTrue(
                GenerationFailure.isInsufficientCredits(apiCode: nil, message: message),
                message
            )
        }
    }

    func testUnrelatedHeartbeatErrorsAreNotConvertedToCreditFailures() {
        for message in [
            "Session expired", "Network connection lost", "Request timed out",
            "Insufficient storage", "Invalid API key", "Credit card payment declined",
            "Too many requests", "安全审核未通过", "网络连接已断开",
        ] {
            XCTAssertFalse(
                GenerationFailure.isInsufficientCredits(apiCode: 503, message: message),
                message
            )
        }
    }
}
