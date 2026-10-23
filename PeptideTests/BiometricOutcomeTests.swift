import LocalAuthentication
import XCTest
@testable import Peptide

final class BiometricOutcomeTests: XCTestCase {

    func test_passcodeNotSet_isUnavailable() {
        XCTAssertEqual(BiometricOutcome(code: .passcodeNotSet), .unavailable)
    }

    func test_cancelCodes_areCancelled() {
        for code: LAError.Code in [.userCancel, .appCancel, .systemCancel] {
            XCTAssertEqual(BiometricOutcome(code: code), .cancelled, "\(code)")
        }
    }

    func test_retryableFailures_areFailed() {
        for code: LAError.Code in [.authenticationFailed, .biometryLockout, .biometryNotEnrolled, .userFallback] {
            XCTAssertEqual(BiometricOutcome(code: code), .failed, "\(code)")
        }
    }
}
