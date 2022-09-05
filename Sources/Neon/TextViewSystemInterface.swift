#if os(macOS)
import AppKit

public typealias TextView = NSTextView
#elseif os(iOS)
import UIKit

public typealias TextView = UITextView
#endif

#if os(macOS) || os(iOS)
public struct TextViewSystemInterface {
	public typealias AttributeProvider = (Token) -> [NSAttributedString.Key: Any]?

	public let textView: TextView
	public let attributeProvider: AttributeProvider

	public init(textView: TextView, attributeProvider: @escaping AttributeProvider) {
		self.textView = textView
		self.attributeProvider = attributeProvider
	}

	public var layoutManager: NSLayoutManager? {
		#if os(macOS)
		return textView.textContainer?.layoutManager
		#else
		return textView.layoutManager
		#endif
	}

	@available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
	public var textLayoutManager: NSTextLayoutManager? {
		#if os(macOS)
		return textView.textContainer?.textLayoutManager
		#else
		return textView.textContainer.textLayoutManager
		#endif
	}

	public var textStorage: NSTextStorage? {
		return textView.textStorage
	}
}

extension TextViewSystemInterface: TextSystemInterface {
	private func setAttributes(_ attrs: [NSAttributedString.Key : Any], in range: NSRange) {
		let endLocation = min(range.max, length)

		assert(endLocation == range.max, "range is out of bounds, is the text state being updated correctly?")

		let clampedRange = NSRange(range.location..<endLocation)

		// try text kit 2 first
		if
			#available(macOS 12, iOS 15.0, tvOS 15.0, *),
			let textLayoutManager = textLayoutManager,
			let contentManager = textLayoutManager.textContentManager,
			let textRange = NSTextRange(clampedRange, provider: contentManager)
		{
			textLayoutManager.setRenderingAttributes(attrs, for: textRange)
			return
		}

		// next, textkit 1
		#if os(macOS)
		if let layoutManager = layoutManager {
			layoutManager.setTemporaryAttributes(attrs, forCharacterRange: clampedRange)
			return
		}
		#endif

		// finally, fall back to applying color directly to the storage
		assert(textStorage != nil, "TextView's NSTextStorage cannot be nil")
		textStorage?.setAttributes(attrs, range: clampedRange)
	}

	public func clearStyle(in range: NSRange) {
		setAttributes([:], in: range)
	}

	public func applyStyle(to token: Token) {
		guard let attrs = attributeProvider(token) else { return }

		setAttributes(attrs, in: token.range)
	}

	public var length: Int {
		return textStorage?.length ?? 0
	}

	public var visibleRange: NSRange {
		return textView.visibleTextRange
	}
}

#endif

