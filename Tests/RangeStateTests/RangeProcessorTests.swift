import XCTest

import RangeState
import Rearrange

@MainActor
final class MockChangeHandler {
	var mutations = [RangeMutation]()

	var changeCompleted: @MainActor () -> Void = { }

	func handleChange(_ mutation: RangeMutation, completion: @MainActor @escaping () -> Void) {
		mutations.append(mutation)

		changeCompleted()
		completion()
	}
}

final class RangeProcessorTests: XCTestCase {
	@MainActor
	func testSynchronousFill() {
		let exp = expectation(description: "mutation")

		let changeHandler: RangeProcessor.ChangeHandler = { mutation, completion in
			XCTAssertEqual(mutation, RangeMutation(range: NSRange(0..<0), delta: 10))
			
			exp.fulfill()
			completion()
		}

		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { 100 },
				changeHandler: changeHandler
			)
		)

		XCTAssertTrue(processor.processLocation(10, mode: .required))

		wait(for: [exp], enforceOrder: true)
	}

	@MainActor
	func testOptionalFill() {
		let exp = expectation(description: "mutation")

		let changeHandler: RangeProcessor.ChangeHandler = { mutation, completion in
			XCTAssertEqual(mutation, RangeMutation(range: NSRange(0..<0), delta: 10))

			exp.fulfill()
			completion()
		}

		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { 100 },
				changeHandler: changeHandler
			)
		)

		XCTAssertFalse(processor.processLocation(10, mode: .optional))

		wait(for: [exp], enforceOrder: true)

		XCTAssert(processor.processed(10))
	}

	@MainActor
	func testInsertWithEverythingProcessed() {
		let exp = expectation(description: "mutation")
		exp.expectedFulfillmentCount = 2

		let handler = MockChangeHandler()

		handler.changeCompleted = {
			exp.fulfill()
		}

		let content = StringContent(string: "abcde")

		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { content.currentLength },
				changeHandler: handler.handleChange
			)
		)

		XCTAssertTrue(processor.processLocation(5, mode: .required))
		XCTAssertTrue(processor.processed(5))

		// insert a character
		content.string = "abcdef"
		processor.didChangeContent(in: NSRange(5..<5), delta: 1)

		wait(for: [exp], enforceOrder: true)

		let expected = [
			RangeMutation(range: NSRange(0..<0), delta: 5, limit: nil),
			RangeMutation(range: NSRange(5..<5), delta: 1, limit: 6),
		]

		XCTAssertEqual(handler.mutations, expected)
	}

	@MainActor
	func testDeleteWithEverythingProcessed() {
		let exp = expectation(description: "mutation")
		exp.expectedFulfillmentCount = 2

		let handler = MockChangeHandler()

		handler.changeCompleted = {
			exp.fulfill()
		}

		let content = StringContent(string: "abcde")

		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { content.currentLength },
				changeHandler: handler.handleChange
			)
		)

		XCTAssertTrue(processor.processLocation(5, mode: .required))
		XCTAssertTrue(processor.processed(5))

		// insert a character
		content.string = "abcd"
		processor.didChangeContent(in: NSRange(4..<5), delta: -1)

		wait(for: [exp], enforceOrder: true)

		let expected = [
			RangeMutation(range: NSRange(0..<0), delta: 5, limit: nil),
			RangeMutation(range: NSRange(4..<5), delta: -1, limit: 5),
		]

		XCTAssertEqual(handler.mutations, expected)
	}
}
