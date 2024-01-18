import XCTest

import RangeState
import Rearrange

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
}
