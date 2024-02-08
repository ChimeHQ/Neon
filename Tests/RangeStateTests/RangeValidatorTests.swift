import XCTest

import RangeState

final class RangeValidatorTests: XCTestCase {
	typealias StringValidator = RangeValidator<StringContent>

	@MainActor
	func testHandleCompletedValidation() {
		let content = StringContent(string: "abc")
		let validator = StringValidator(content: content)

		let range = NSRange(0..<3)
		let contentRange = StringValidator.ContentRange(range, version: content.currentVersion)

		let val1 = validator.beginValidation(of: .all)

		XCTAssertEqual(val1, .needed(contentRange))

		validator.completeValidation(of: contentRange, with: .success(range))

		let val2 = validator.beginValidation(of: .all)

		XCTAssertEqual(val2, .none)
	}

	@MainActor
	func testHandleDuplicateValidation() {
		let content = StringContent(string: "abc")
		let validator = StringValidator(content: content)

		let range = NSRange(0..<3)
		let contentRange = StringValidator.ContentRange(range, version: content.currentVersion)

		let val1 = validator.beginValidation(of: .all)

		XCTAssertEqual(val1, .needed(contentRange))

		let val2 = validator.beginValidation(of: .all)

		XCTAssertEqual(val2, .none)
	}
}
