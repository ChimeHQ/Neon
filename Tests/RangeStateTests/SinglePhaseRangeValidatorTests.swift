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
			asyncValue: { _, contentRange in
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
			asyncValue: { _, contentRange in
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
			asyncValue: { _, contentRange in
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
    
	@MainActor
	func testContentAddedAtEndAsync() async {
		let validationExp = expectation(description: "validation")

		let content = StringContent(string: "abc")
		let provider = StringValidator.Provider(
			syncValue: { _ in
				return nil
			},
			asyncValue: { _, contentRange in
				validationExp.fulfill()

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
	func testDistinctPrioritySetValidation() async {
		let validationExp = expectation(description: "validation")
		validationExp.expectedFulfillmentCount = 2
		var validatedRanges = [NSRange]()

		let content = StringContent(string: "aaabbbccc")
		let provider = StringValidator.Provider(
			syncValue: { _ in
				return nil
			},
			asyncValue: { _, contentRange in
				validationExp.fulfill()
				validatedRanges.append(contentRange.value)

				return .success(contentRange.value)
			}
		)

		let validator = StringValidator(
			configuration: .init(
				versionedContent: content,
				provider: provider
			)
		)

		let prioritySet = IndexSet(ranges: [
			NSRange(0..<3),
			NSRange(6..<9),
		])
		
		validator.validate(.set(prioritySet))
		await fulfillment(of: [validationExp], timeout: 1.0)

		XCTAssertEqual(validatedRanges, prioritySet.nsRangeView)
	}

	@MainActor
	func testDistinctInvalidRegions() async {
		var validatedRanges = [NSRange]()

		let content = StringContent(string: "aaabbbccc")
		let provider = StringValidator.Provider(
			syncValue: { _ in
				return nil
			},
			asyncValue: { _, contentRange in
				validatedRanges.append(contentRange.value)

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
		await validator.validationCompleted(isolation: MainActor.shared)

		let set = IndexSet(ranges: [
			NSRange(0..<3),
			NSRange(6..<9),
		])

		// now we can invalidate two distinct regions
		validator.invalidate(.set(set))
		validator.validate(.all)

		await validator.validationCompleted(isolation: MainActor.shared)

		let expectedRanges = [
			NSRange(0..<9),
			NSRange(0..<3),
			NSRange(6..<9),
		]
		XCTAssertEqual(validatedRanges, expectedRanges)
	}
}
