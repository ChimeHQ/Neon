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
	public var defaultTextViewAttributes: [NSAttributedString.Key: Any] = [:]

	public init(
		textView: TextView,
		defaultTextViewAttributes: [NSAttributedString.Key: Any] = [:],
		attributeProvider: @escaping AttributeProvider
	) {
		self.textView = textView
		// Assume that the default styles used before enabling any highlighting
		// should be retained, unless client code overrides this.
		self.defaultTextViewAttributes = [
			 .font: textView.font as Any,
			 .foregroundColor: textView.textColor as Any,
		].merging(defaultTextViewAttributes) { _, override in override }
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
	private func clamped(range: NSRange) -> NSRange {
		let endLocation = min(range.max, length)

		assert(endLocation == range.max, "range is out of bounds, is the text state being updated correctly?")

		return NSRange(range.location..<endLocation)
	}

	private func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, in range: NSRange) {
		let clampedRange = clamped(range: range)

		// Both `NSTextLayoutManager.setRenderingAttributes` and
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

