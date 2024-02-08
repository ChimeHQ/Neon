import XCTest

import RangeState

final class SinglePhaseRangeValidatorTests: XCTestCase {
	typealias StringValidator = SinglePhaseRangeValidator<StringContent>

	@MainActor
	func testContentAddedAtEnd() async {
		let validationExp = expectation(description: "validation")

		let content = StringContent(string: "abc")
		let provider = StringValidator.Provider(
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
				provider: provider
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

		let content = StringContent(string: "abc")
		let provider = StringValidator.Provider(
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
				provider: provider
			)
		)

		validator.validate(.all)

		await fulfillment(of: [validationExp], timeout: 1.0)

		content.string = "ac"
		validator.contentChanged(in: NSRange(1..<2), delta: -1)
	}

	@MainActor
	func testContentDeletedAtEnd() async {
		let validationExp = expectation(description: "validation")

		let content = StringContent(string: "abc")
		let provider = StringValidator.Provider(
			syncValue: {
				validationExp.fulfill()
				
				return .success($0.value)
			},
			asyncValue: { contentRange, _ in
				return .success(contentRange.value)
			}
		)

		let validator = StringValidator(
			configuration: .init(
				versionedContent: content,
				provider: provider
			)
		)

		validator.validate(.all)

		await fulfillment(of: [validationExp], timeout: 1.0)

		content.string = "ab"
		validator.contentChanged(in: NSRange(2..<3), delta: -1)
	}
}
