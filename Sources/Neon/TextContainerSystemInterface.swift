#if os(macOS)
import AppKit
import Rearrange

@available(*, deprecated, message: "TextViewSystemInterface should be used instead")
public struct TextContainerSystemInterface {
    public typealias AttributeProvider = (Token) -> [NSAttributedString.Key: Any]?

    public let textContainer: NSTextContainer
    public let attributeProvider: AttributeProvider

    public init(textContainer: NSTextContainer, attributeProvider: @escaping AttributeProvider) {
        self.textContainer = textContainer
        self.attributeProvider = attributeProvider
    }

    public var layoutManager: NSLayoutManager? {
        return textContainer.layoutManager
    }

	@available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
	public var textLayoutManager: NSTextLayoutManager? {
		return textContainer.textLayoutManager
	}
}

@available(*, deprecated, message: "TextViewSystemInterface should be used instead")
extension TextContainerSystemInterface: TextSystemInterface {
	private func setAttributes(_ attrs: [NSAttributedString.Key : Any], in range: NSRange) {
		let endLocation = min(range.max, length)

		assert(endLocation == range.max, "range is out of bounds, is the text state being updated correctly?")

		let clampedRange = NSRange(range.location..<endLocation)

		#if os(macOS)
		layoutManager?.setTemporaryAttributes(attrs, forCharacterRange: clampedRange)
		#endif

		guard
			#available(macOS 12, iOS 15.0, tvOS 15.0, *),
			let textLayoutManager = textLayoutManager,
			let contentManager = textLayoutManager.textContentManager,
			let textRange = NSTextRange(clampedRange, provider: contentManager)
		else {
			return
		}

		textLayoutManager.setRenderingAttributes(attrs, for: textRange)
	}

    public func clearStyle(in range: NSRange) {
		setAttributes([:], in: range)
    }

    public func applyStyle(to token: Token) {
        guard let attrs = attributeProvider(token) else { return }

		setAttributes(attrs, in: token.range)
    }

    public var length: Int {
        return layoutManager?.textStorage?.length ?? 0
    }

    public var visibleRange: NSRange {
        return textContainer.textView?.visibleTextRange ?? .zero
    }
}

#endif
