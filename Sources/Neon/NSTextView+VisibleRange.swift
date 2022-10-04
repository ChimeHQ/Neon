#if os(macOS)
import AppKit

extension NSTextView {
	func textRange(for rect: CGRect) -> NSRange {
		let length = self.textStorage?.length ?? 0

		// If we have a textLayoutManager, the view is using TextKit2
		// and we shouldn't be responsible for converting it to TextKit1.
		// In the future it might be useful to implement a version of
		// this method that works correctly with the TextKit2 API to
		// generate an accurate range for the given rect.
		if #available(macOS 12.0, *) {
			if self.textLayoutManager != nil {
				return NSRange(0..<length)
			}
		}

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
