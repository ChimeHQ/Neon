import XCTest

import RangeState

final class RangeValidatorTests: XCTestCase {
	typealias StringValidator = RangeValidator<StringContent>

	@MainActor
	func testContentChange() async {
		let validationExp = expectation(description: "validation")

		var content = StringContent(string: "abc")
		let provider = StringValidator.ValidationProvider(
			syncValue: {
				validationExp.fulfill()

				return .success($0.value)
			},
			asyncValue: { contentRange, _ in
				return .success(contentRange.value)
			})

		let validator = StringValidator(
			configuration: .init(
				versionedContent: content,
				validationProvider: provider
			)
		)

		validator.validate(.all)

		await fulfillment(of: [validationExp], timeout: 1.0)

		content.string = "abcd"
		validator.contentChanged(in: NSRange(3..<3), delta: 1)
	}

	@MainActor
	func testContentDeleted() async {
		let validationExp = expectation(description: "validation")

		var content = StringContent(string: "abc")
		let provider = StringValidator.ValidationProvider(
			syncValue: {
				validationExp.fulfill()

				return .success($0.value)
			},
			asyncValue: { contentRange, _ in
				return .success(contentRange.value)
			})

		let validator = StringValidator(
			configuration: .init(
				versionedContent: content,
				validationProvider: provider
			)
		)

		validator.validate(.all)

		await fulfillment(of: [validationExp], timeout: 1.0)

		content.string = "ac"
		validator.contentChanged(in: NSRange(1..<2), delta: -1)
	}
}
