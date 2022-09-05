#if os(macOS)
import AppKit
import XCTest
@testable import Neon

@available(*, deprecated, message: "TextViewSystemInterface should be used instead")
final class TextContainerSystemInterfaceTests: XCTestCase {
	func testApplyAttributes() throws {
		let textView = NSTextView()
		let container = try XCTUnwrap(textView.textContainer)

		let provider: TextContainerSystemInterface.AttributeProvider = { _ in
			return [.foregroundColor: NSColor.red]
		}

		let system = TextContainerSystemInterface(textContainer: container, attributeProvider: provider)

		textView.string = "abc123"

		system.applyStyle(to: Token(name: "test", range: NSRange(0..<6)))

		var effectiveRange: NSRange = .zero

		let attrs = textView.layoutManager?.temporaryAttributes(atCharacterIndex: 0, effectiveRange: &effectiveRange)

		XCTAssertEqual(attrs?.count, 1)
		XCTAssertEqual(attrs?[.foregroundColor] as? NSColor, NSColor.red)
		XCTAssertEqual(effectiveRange, NSRange(0..<6))
	}
}

#endif
