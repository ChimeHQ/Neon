import XCTest
import Neon
import TreeSitterClient

class MockInterface: TextSystemInterface {
    var length: Int
    var visibleRange: NSRange

    init(length: Int = 0, visibleRange: NSRange = .zero) {
        self.length = length
        self.visibleRange = visibleRange
    }

    func clearStyle(in range: NSRange) {
    }

    func applyStyle(to token: Token) {
    }
}

class HighlighterTests: XCTestCase {
    func testEditAndVisibleRangeChange() throws {
        let interface = MockInterface()

        var requestedRange: NSRange? = nil
        let provider: TokenProvider = { range, block in
            requestedRange = range
            block(.success(.noChange))
        }

        let highlighter = Highlighter(textInterface: interface, tokenProvider: provider)

        interface.length = 10
        highlighter.didChangeContent(in: NSRange(0..<0), delta: 10)

        interface.visibleRange = NSRange(0..<10)
        highlighter.visibleContentDidChange()

        XCTAssertEqual(requestedRange, NSRange(0..<10))
    }
}
