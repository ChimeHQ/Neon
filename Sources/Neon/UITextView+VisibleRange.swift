#if os(iOS)
import UIKit
import Rearrange

extension UITextView {
	var visibleTextRange: NSRange {
		let endPoint = CGPoint(x: contentOffset.x + bounds.maxX, y: contentOffset.y + bounds.maxY)

		guard
			let start = closestPosition(to: contentOffset),
			let end = characterRange(at: endPoint)?.end,
			let tRange = textRange(from: start, to: end),
			let range = NSRange(tRange, textView: self)
		else {
			return NSRange(0..<textStorage.length)
		}

		return range
	}
}

#endif
