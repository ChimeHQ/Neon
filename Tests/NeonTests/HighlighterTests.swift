import XCTest
@testable import Neon

//class MockInterface: TextSystemInterface {
//    var length: Int
//    var visibleRange: NSRange
//
//    init(length: Int = 0, visibleRange: NSRange = .zero) {
//        self.length = length
//        self.visibleRange = visibleRange
//    }
//
//    func clearStyle(in range: NSRange) {
//    }
//
//    func applyStyle(to token: Token) {
//    }
//}
//
//final class HighlighterTests: XCTestCase {
//	@MainActor
//    func testEditAndVisibleRangeChange() throws {
//        let interface = MockInterface(length: 10, visibleRange: NSRange(0..<10))
//
//        var requestedRange: NSRange? = nil
//        let provider: TokenProvider = { range, block in
//            requestedRange = range
//            block(.success(.noChange))
//        }
//
//        let highlighter = Highlighter(textInterface: interface, tokenProvider: provider)
//
//        highlighter.didChangeContent(in: NSRange(0..<0), delta: 10)
//        highlighter.visibleContentDidChange()
//
//        XCTAssertEqual(requestedRange, NSRange(0..<10))
//    }
//
//	@MainActor
//	func testValidSetDefinedByEffectiveRange() throws {
//		let interface = MockInterface(length: 100, visibleRange: NSRange(0..<100))
//
//		let expectation = XCTestExpectation(description: "request expectation")
//		expectation.expectedFulfillmentCount = 1
//
//		var requestedRanges = [NSRange]()
//		let provider: TokenProvider = { range, block in
//			requestedRanges.append(range)
//
//			if requestedRanges.count == 1 {
//				let token = Token(name: "abc", range: NSRange(0..<10))
//				let app = TokenApplication(tokens: [token], range: token.range)
//
//				block(.success(app))
//			} else {
//				block(.success(.noChange))
//
//				expectation.fulfill()
//			}
//		}
//
//		let highlighter = Highlighter(textInterface: interface, tokenProvider: provider)
//
//		highlighter.visibleContentDidChange()
//
//		XCTAssertEqual(requestedRanges.count, 1)
//		XCTAssertEqual(requestedRanges.last, NSRange(0..<100))
//
//		wait(for: [expectation], timeout: 1.0)
//
//		XCTAssertEqual(requestedRanges.count, 2)
//		XCTAssertEqual(requestedRanges.last, NSRange(10..<100))
//	}
//
//	@MainActor
//	func testValidSetDefinedByTokensOutsideValidRange() throws {
//		let interface = MockInterface(length: 100, visibleRange: NSRange(0..<50))
//
//		let expectation = XCTestExpectation(description: "request expectation")
//		expectation.expectedFulfillmentCount = 1
//
//		var requestedRanges = [NSRange]()
//		let provider: TokenProvider = { range, block in
//			requestedRanges.append(range)
//
//			if requestedRanges.count == 1 {
//				let tokenA = Token(name: "abc", range: NSRange(0..<1))
//				let tokenB = Token(name: "abc", range: NSRange(50..<51))
//				let app = TokenApplication(tokens: [tokenA, tokenB])
//
//				block(.success(app))
//			} else {
//				block(.success(.noChange))
//
//				expectation.fulfill()
//			}
//		}
//
//		let highlighter = Highlighter(textInterface: interface, tokenProvider: provider)
//		highlighter.requestLengthLimit = 50
//
//		highlighter.visibleContentDidChange()
//		interface.visibleRange = NSRange(0..<100)
//
//		XCTAssertEqual(requestedRanges.count, 1)
//		XCTAssertEqual(requestedRanges.last, NSRange(0..<50))
//
//		wait(for: [expectation], timeout: 1.0)
//
//		XCTAssertEqual(requestedRanges.count, 2)
//
//		// this should take into account the extra bit of token data we returned
//		XCTAssertEqual(requestedRanges.last, NSRange(51..<100))
//	}
//
//	@MainActor
//	func testConsolidateInvalidRanges() throws {
//		let interface = MockInterface(length: 100, visibleRange: NSRange(0..<100))
//
//		let expectation = XCTestExpectation(description: "request expectation")
//		expectation.expectedFulfillmentCount = 1
//
//		var requestedRanges = [NSRange]()
//		let provider: TokenProvider = { range, block in
//			requestedRanges.append(range)
//
//			if requestedRanges.count == 1 {
//				let token = Token(name: "abc", range: NSRange(0..<100))
//				let app = TokenApplication(tokens: [token], range: token.range)
//
//				block(.success(app))
//			} else {
//				block(.success(.noChange))
//
//				expectation.fulfill()
//			}
//		}
//
//		let highlighter = Highlighter(textInterface: interface, tokenProvider: provider)
//		highlighter.requestLengthLimit = 100
//
//		highlighter.visibleContentDidChange()
//
//		XCTAssertEqual(requestedRanges.count, 1)
//		XCTAssertEqual(requestedRanges.last, NSRange(0..<100))
//
//		var invalidSet = IndexSet()
//
//		invalidSet.insert(0)
//		invalidSet.insert(50)
//		invalidSet.insert(99)
//
//		highlighter.invalidate(.set(invalidSet))
//
//		wait(for: [expectation], timeout: 1.0)
//
//		XCTAssertEqual(requestedRanges.count, 2)
//		XCTAssertEqual(requestedRanges.last, NSRange(0..<100))
//	}
//}
