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

	var defaultTextViewAttributes: [NSAttributedString.Key: Any] {
		[
			.font: textView.font as Any,
			.foregroundColor: textView.textColor as Any,
		]
	}
}

extension TextViewSystemInterface: TextSystemInterface {
	private func clamped(range: NSRange) -> NSRange {
		let endLocation = min(range.max, length)

		assert(endLocation == range.max, "range is out of bounds, is the text state being updated correctly?")

		return NSRange(range.location..<endLocation)
	}

	private func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, in range: NSRange) {
		let clampedRange = clamped(range: range)

		// Try TextKit 2 first
		if
			#available(macOS 12, iOS 15.0, tvOS 15.0, *),
			let textLayoutManager = textLayoutManager,
			let contentManager = textLayoutManager.textContentManager,
			let textRange = NSTextRange(clampedRange, provider: contentManager)
		{
			// TextKit 2 uses temporary rendering attributes. These can be
			// overwritten to clear.
			let attrs = attrs ?? [:]
			textLayoutManager.setRenderingAttributes(attrs, for: textRange)
			return
		}

		// For TextKit 1: Fall back to applying styles directly to the storage.
		// `NSLayoutManager.setTemporaryAttributes` is limited to attributes
		// that don't affect layout, like color. So it ignores fonts,
		// making font weight changes or italicizing text impossible.
		assert(textStorage != nil, "TextView's NSTextStorage cannot be nil")
		let attrs = attrs ?? defaultTextViewAttributes
		textStorage?.setAttributes(attrs, range: clampedRange)
	}

	public func clearStyle(in range: NSRange) {
		setAttributes(nil, in: range)
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

