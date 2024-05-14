import XCTest
@testable import Neon

#if os(macOS)
import AppKit

extension NSTextView {
	var text: String {
		get { return string }
		set { string = newValue }
	}

	@available(macOS 12.0, *)
	static func textKit2View() -> NSTextView {
		if #available(macOS 13.0, *) {
			return NSTextView()
		}

		let textContainer = NSTextContainer(size: CGSize(width: 0.0, height: 1.0e7))
		let textContentManager = NSTextContentStorage()
		let textLayoutManager = NSTextLayoutManager()
		textLayoutManager.textContainer = textContainer
		textContentManager.addTextLayoutManager(textLayoutManager)

		return NSTextView(frame: .zero, textContainer: textContainer)
	}
}

#elseif os(iOS)
import UIKit

#endif

//final class TextViewSystemInterfaceTests: XCTestCase {
//#if os(macOS) || os(iOS)
//	@MainActor
//	func testApplyAttributesToTextView() throws {
//		let textView = TextView()
//
//		XCTAssertNotNil(textView.layoutManager)
//
//		let provider: TokenAttributeProvider = { _ in
//			return [.foregroundColor: PlatformColor.red]
//		}
//
//		let system = TextViewSystemInterface(textView: textView, attributeProvider: provider)
//
//		textView.text = "abc123"
//
//		system.applyStyle(to: Token(name: "test", range: NSRange(0..<6)))
//
//		var effectiveRange: NSRange = .zero
//
//		#if os(macOS)
//		let attrs = textView.layoutManager?.temporaryAttributes(atCharacterIndex: 0, effectiveRange: &effectiveRange) ?? [:]
//		#else
//		let allAttrs = textView.textStorage.attributes(at: 0, effectiveRange: &effectiveRange)
//
//		// we have to remove some attributes, like font, that are normal for the textStorage.
//		let attrs = allAttrs.filter({ $0.key == .foregroundColor })
//		#endif
//
//		XCTAssertEqual(attrs.count, 1)
//		XCTAssertEqual(attrs[.foregroundColor] as? PlatformColor, PlatformColor.red)
//		XCTAssertEqual(effectiveRange, NSRange(0..<6))
//
//	}
//#endif
//
//#if os(macOS) || os(iOS)
//	@available(macOS 12.0, iOS 15.0, *)
//	@MainActor
//	func testApplyAttributesToTextKit2TextView() throws {
//		#if os(macOS)
//		let textView = NSTextView.textKit2View()
//		let textLayoutManager = try XCTUnwrap(textView.textLayoutManager)
//		#else
//		let textView = UITextView()
//
//		let textLayoutManager = try XCTUnwrap(textView.textContainer.textLayoutManager)
//		#endif
//
//		let provider: TokenAttributeProvider = { _ in
//			return [.foregroundColor: PlatformColor.red]
//		}
//
//		let system = TextViewSystemInterface(textView: textView, attributeProvider: provider)
//
//		textView.text = "abc123"
//
//		system.applyStyle(to: Token(name: "test", range: NSRange(0..<6)))
//
//		let documentRange = textLayoutManager.documentRange
//
//		var attrRangePairs = [([NSAttributedString.Key: Any], NSTextRange)]()
//
//		textLayoutManager.enumerateRenderingAttributes(from: documentRange.location, reverse: false, using: { _, attrs, range in
//			attrRangePairs.append((attrs, range))
//
//			return true
//		})
//
//		XCTAssertEqual(attrRangePairs.count, 1)
//
//		let firstPair = try XCTUnwrap(attrRangePairs.first)
//
//		XCTAssertEqual(firstPair.0[.foregroundColor] as? PlatformColor, PlatformColor.red)
//		XCTAssertEqual(firstPair.1, documentRange)
//	}
//#endif
//
//#if os(macOS) || os(iOS)
//	@available(macOS 12.0, iOS 15.0, *)
//	@MainActor
//	func testVisibleTextRangePreservesTextKit2() throws {
//		#if os(macOS)
//		let textView = NSTextView.textKit2View()
//
//		XCTAssertNotNil(textView.textLayoutManager)
//		let _ = textView.visibleTextRange
//		XCTAssertNotNil(textView.textLayoutManager)
//		#else
//		let textView = UITextView()
//
//		XCTAssertNotNil(textView.textContainer.textLayoutManager)
//		let _ = textView.visibleTextRange
//		XCTAssertNotNil(textView.textContainer.textLayoutManager)
//		#endif
//	}
//#endif
//}
//
