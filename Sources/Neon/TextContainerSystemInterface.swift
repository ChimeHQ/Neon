import Foundation
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
}

extension TextContainerSystemInterface: TextSystemInterface {
    public func clearStyle(in range: NSRange) {
        assert(range.max <= length, "range is out of bounds, is the text state being updated correctly?")

        layoutManager?.setTemporaryAttributes([:], forCharacterRange: range)
    }

    public func applyStyle(to token: Token) {
        assert(token.range.max <= length, "range is out of bounds, is the text state being updated correctly?")

        guard let attrs = attributeProvider(token) else { return }

        layoutManager?.setTemporaryAttributes(attrs, forCharacterRange: token.range)
    }

    public var length: Int {
        return layoutManager?.textStorage?.length ?? 0
    }

    public var visibleRange: NSRange {
        return textContainer.textView?.visibleTextRange ?? .zero
    }
}

#endif
