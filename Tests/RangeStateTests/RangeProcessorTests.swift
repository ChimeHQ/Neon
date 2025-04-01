import XCTest

import RangeState
import Rearrange

final class MockChangeHandler {
	var mutations = [RangeMutation]()

	var changeCompleted: (RangeMutation) -> Void = { _ in }

	func handleChange(_ mutation: RangeMutation, completion: @escaping () -> Void) {
		mutations.append(mutation)

		changeCompleted(mutation)
		completion()
	}
}

import Testing

struct RangeProcessorTests {
	@Test func synchronousFill() async {
		var changedEvent: CheckedContinuation<RangeMutation, Never>?
		
		let changeHandler: RangeProcessor.ChangeHandler = { mutation, completion in
			completion()
			changedEvent!.resume(returning: mutation)
		}

		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { 100 },
				changeHandler: changeHandler
			)
		)

		let mutation = await withCheckedContinuation { continuation in
			changedEvent = continuation
			
			#expect(processor.processLocation(10, mode: .required))
		}
		
		#expect(mutation == RangeMutation(range: NSRange(0..<0), delta: 11))
	}
	
	@Test func optionalFill() async {
		var changedEvent: CheckedContinuation<RangeMutation, Never>?

		let changeHandler: RangeProcessor.ChangeHandler = { mutation, completion in
			completion()
			changedEvent!.resume(returning: mutation)
		}

		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { 100 },
				changeHandler: changeHandler
			)
		)

		let mutation = await withCheckedContinuation { continuation in
			changedEvent = continuation
			
			#expect(processor.processLocation(10, mode: .optional) == false)
		}
		
		#expect(mutation == RangeMutation(range: NSRange(0..<0), delta: 11))
		#expect(processor.processed(10))
	}
	
	@Test func processSingleCharacterString() async throws {
		let content = StringContent(string: "a")
		
		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { content.currentLength },
				changeHandler: { $1() }
			)
		)

		#expect(processor.processLocation(0, mode: .required))
	}
	
	@Test func insertWithNothingProcessed() {
		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { 10 },
				changeHandler: { _, _ in fatalError() }
			)
		)

		processor.didChangeContent(in: NSRange(0..<10), delta: 10)
	}
	
	@Test func processWithEmptyContent() {
		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { 0 },
				changeHandler: { _, _ in fatalError() }
			)
		)

		#expect(processor.processLocation(0, mode: .required) == false)
		#expect(processor.processed(0) == false)
	}

	@Test func insertWithEverythingProcessed() async {
		let content = StringContent(string: "abcde")
		let handler = MockChangeHandler()
		
		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { content.currentLength },
				changeHandler: handler.handleChange
			)
		)

		let mutation1 = await withCheckedContinuation { continuation in
			handler.changeCompleted = {
				continuation.resume(returning: $0)
			}
			
			#expect(processor.processLocation(4, mode: .required))
			#expect(processor.processed(4))
		}
		
		#expect(mutation1 == RangeMutation(range: NSRange(0..<0), delta: 5, limit: nil))
		
		// insert a character
		let mutation2 = await withCheckedContinuation { continuation in
			handler.changeCompleted = {
				continuation.resume(returning: $0)
			}
			
			content.string = "abcdef"
			processor.didChangeContent(in: NSRange(5..<5), delta: 1)
			
			// and now actually ask for the new position
			#expect(processor.processLocation(5, mode: .required))
		}
		
		#expect(mutation2 == RangeMutation(range: NSRange(5..<5), delta: 1, limit: nil))
	}
	
	@Test func deleteWithEverythingProcessed() async {
		let content = StringContent(string: "abcde")
		let handler = MockChangeHandler()
		
		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { content.currentLength },
				changeHandler: handler.handleChange
			)
		)

		let mutation1 = await withCheckedContinuation { continuation in
			handler.changeCompleted = {
				continuation.resume(returning: $0)
			}
			
			#expect(processor.processLocation(4, mode: .required))
			#expect(processor.processed(4))
		}
		
		#expect(mutation1 == RangeMutation(range: NSRange(0..<0), delta: 5, limit: nil))

		// remove a character
		let mutation2 = await withCheckedContinuation { continuation in
			handler.changeCompleted = {
				continuation.resume(returning: $0)
			}
			
			content.string = "abcd"
			processor.didChangeContent(in: NSRange(4..<5), delta: -1)
			
			// already processed so should happen automatically
		}
		
		#expect(mutation2 == RangeMutation(range: NSRange(4..<5), delta: -1, limit: 5))
	}
	
	@Test func deleteEverythingAfterProcessing() async {
		let content = StringContent(string: "abcde")
		let handler = MockChangeHandler()
		
		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { content.currentLength },
				changeHandler: handler.handleChange
			)
		)

		let mutation1 = await withCheckedContinuation { continuation in
			handler.changeCompleted = {
				continuation.resume(returning: $0)
			}
			
			#expect(processor.processLocation(4, mode: .required))
			#expect(processor.processed(4))
		}
		
		#expect(mutation1 == RangeMutation(range: NSRange(0..<0), delta: 5, limit: nil))

		// remove all content
		let mutation2 = await withCheckedContinuation { continuation in
			handler.changeCompleted = {
				continuation.resume(returning: $0)
			}
			
			content.string = ""
			processor.didChangeContent(in: NSRange(0..<5), delta: -5)

		}
		
		#expect(mutation2 == RangeMutation(range: NSRange(0..<5), delta: -5, limit: 5))
	}

	@Test func changeThatOverlapsUnprocessedRegion() async {
		let content = StringContent(string: "abcdefghij")
		let handler = MockChangeHandler()
		
		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { content.currentLength },
				changeHandler: handler.handleChange
			)
		)

		let mutation1 = await withCheckedContinuation { continuation in
			handler.changeCompleted = {
				continuation.resume(returning: $0)
			}
			
			// process half
			#expect(processor.processLocation(4, mode: .required))
			#expect(processor.processed(4))
		}
		
		#expect(mutation1 == RangeMutation(range: NSRange(0..<0), delta: 5, limit: nil))


		// change everything
		let mutation2 = await withCheckedContinuation { continuation in
			handler.changeCompleted = {
				continuation.resume(returning: $0)
			}
			
			processor.didChangeContent(in: NSRange(0..<10), delta: 0)
		}

		#expect(mutation2 == RangeMutation(range: NSRange(0..<5), delta: 0, limit: 5))
	}
	
	@MainActor
	@Test func waitForDelayedProcessing() async throws {
		let content = StringContent(string: "abcdefghij")

		let processor = RangeProcessor(
			configuration: .init(
				lengthProvider: { content.currentLength },
				changeHandler: { _, completion in
					// I *think* that a single runloop turn will be enough
					DispatchQueue.main.async() {
						completion()
					}
				}
			)
		)

		// process everything, so there is no more filling needed when complete
		#expect(processor.processLocation(9, mode: .required) == false)

		await processor.processingCompleted(isolation: MainActor.shared)

		#expect(processor.processed(9))
	}
}
