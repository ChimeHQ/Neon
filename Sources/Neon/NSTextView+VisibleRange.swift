#if os(macOS)
import AppKit

extension NSTextView {
	func textRange(for rect: CGRect) -> NSRange {
		let length = self.textStorage?.length ?? 0

		guard let layoutManager = self.layoutManager else {
			return NSRange(0..<length)
		}

		guard let container = self.textContainer else {
			return NSRange(0..<length)
		}

		let origin = textContainerOrigin
		let offsetRect = rect.offsetBy(dx: -origin.x, dy: -origin.y)

		let glyphRange = layoutManager.glyphRange(forBoundingRect: offsetRect, in: container)

		return layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
	}

	var visibleTextRange: NSRange {
		return textRange(for: visibleRect)
	}
}
#endif
