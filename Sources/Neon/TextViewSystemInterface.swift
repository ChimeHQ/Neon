#if os(macOS)
import AppKit

public typealias TextView = NSTextView
#elseif os(iOS)
import UIKit

public typealias TextView = UITextView
#endif

import Rearrange

public typealias TokenAttributeProvider = (Token) -> [NSAttributedString.Key: Any]

#if os(macOS) || os(iOS)
/// A concrete ``TextSystemInterface`` that connects directly to an `NSTextView`/`UITextView`.
///
/// This class can help you get started applying styles to a text view quickly. It prioritizes simplicity and compatibility. It will use the available layout systems's ephemeral attributes if available, and fall back to directly modifying the underlying `NSTextStorage`. 
///
/// Transiting the view from TextKit 2 to TextKit 1 is supported.
///
/// > Note: Consider checking out ``LayoutManagerSystemInterface``, ``TextLayoutManagerSystemInterface``, or ``TextStorageSystemInterface``. These is recommended if you know what behavior you'd like. Alternatively, you can always create your own ``TextSystemInterface`` for complete control.
@MainActor
public struct TextViewSystemInterface {
	public let textView: TextView
	public let attributeProvider: TokenAttributeProvider

	public init(
		textView: TextView,
		attributeProvider: @escaping TokenAttributeProvider
	) {
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
	private var effectiveInterface: TextSystemInterface? {
		let provider = { textView.visibleTextRange }

		if #available(macOS 12.0, iOS 16.0, tvOS 16.0, *) {
			if let textLayoutManager {
				return TextLayoutManagerSystemInterface(
					textLayoutManager: textLayoutManager,
					attributeProvider: attributeProvider,
					visibleRangeProvider: provider
				)
			}
		}

#if os(macOS)
		if let layoutManager {
			return LayoutManagerSystemInterface(
				layoutManager: layoutManager,
				attributeProvider: attributeProvider,
				visibleRangeProvider: provider
			)
		}
#endif

		if textStorage != nil {
			return TextStorageSystemInterface(
				textView: textView,
				attributeProvider: attributeProvider
			)
		}

		return nil
	}

	public func clearStyle(in range: NSRange) {
		effectiveInterface?.clearStyle(in: range)
	}

	public func applyStyle(to token: Token) {
		effectiveInterface?.applyStyle(to: token)
	}

	public var length: Int {
		return textStorage?.length ?? 0
	}

	public var visibleRange: NSRange {
		return textView.visibleTextRange
	}
}

#endif

#if os(macOS)
/// A concrete ``TextSystemInterface`` that uses `NSLayoutManager` temporary attributes.
@MainActor
public struct LayoutManagerSystemInterface {
	public let layoutManager: NSLayoutManager
	public let attributeProvider: TokenAttributeProvider
	public let visibleRangeProvider: () -> NSRange

	public init(layoutManager: NSLayoutManager, attributeProvider: @escaping TokenAttributeProvider, visibleRangeProvider: @escaping () -> NSRange) {
		self.layoutManager = layoutManager
		self.attributeProvider = attributeProvider
		self.visibleRangeProvider = visibleRangeProvider
	}

	public init?(textView: TextView, attributeProvider: @escaping TokenAttributeProvider) {
		guard let layoutManager = textView.layoutManager else { return nil }
		self.layoutManager = layoutManager
		self.visibleRangeProvider = { textView.visibleTextRange }
		self.attributeProvider = attributeProvider
	}
}

extension LayoutManagerSystemInterface: TextSystemInterface {
	private func setAttributes(_ attrs: [NSAttributedString.Key : Any], in range: NSRange) {
		let clampedRange = range.clamped(to: length)

		layoutManager.setTemporaryAttributes(attrs, forCharacterRange: clampedRange)
	}

	public func clearStyle(in range: NSRange) {
		setAttributes([:], in: range)
	}
	
	public func applyStyle(to token: Token) {
		let attrs = attributeProvider(token)

		setAttributes(attrs, in: token.range)
	}
	
	public var length: Int {
		layoutManager.textStorage?.length ?? 0
	}
	
	public var visibleRange: NSRange {
		visibleRangeProvider()
	}
}
#endif

/// A concrete ``TextSystemInterface`` that uses `NSTextLayoutManager` rendering attributes.
@available(macOS 12.0, iOS 16.0, tvOS 16.0, *)
@MainActor
public struct TextLayoutManagerSystemInterface {
	public let textLayoutManager: NSTextLayoutManager
	public let attributeProvider: TokenAttributeProvider
	public let visibleRangeProvider: () -> NSRange

	public init(textLayoutManager: NSTextLayoutManager, attributeProvider: @escaping TokenAttributeProvider, visibleRangeProvider: @escaping () -> NSRange) {
		self.textLayoutManager = textLayoutManager
		self.attributeProvider = attributeProvider
		self.visibleRangeProvider = visibleRangeProvider
	}

	public init?(textView: TextView, attributeProvider: @escaping TokenAttributeProvider) {
		guard let textLayoutManager = textView.textLayoutManager else { return nil }
		self.textLayoutManager = textLayoutManager
		self.visibleRangeProvider = { textView.visibleTextRange }
		self.attributeProvider = attributeProvider
	}
}

@available(macOS 12.0, iOS 16.0, tvOS 16.0, *)
extension TextLayoutManagerSystemInterface: TextSystemInterface {
	private var textElementProvider: NSTextElementProvider? {
		textLayoutManager.textContentManager
	}

	private func setAttributes(_ attrs: [NSAttributedString.Key : Any], in range: NSRange) {
		let clampedRange = range.clamped(to: length)

		guard
			let contentManager = textElementProvider,
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
		let attrs = attributeProvider(token)

		setAttributes(attrs, in: token.range)
	}

	public var length: Int {
		guard let textElementProvider = textElementProvider else { return 0 }

		return NSRange(textLayoutManager.documentRange, provider: textElementProvider).length
	}

	public var visibleRange: NSRange {
		visibleRangeProvider()
	}
}

/// A concrete `TextSystemInterface` that modifies `NSTextStorage` text attributes.
@MainActor
public struct TextStorageSystemInterface {
	private let textStorage: NSTextStorage?
	public let attributeProvider: TokenAttributeProvider
	public let defaultAttributesProvider: () -> [NSAttributedString.Key : Any]
	public let visibleRangeProvider: () -> NSRange

	public init(
		textStorage: NSTextStorage,
		attributeProvider: @escaping TokenAttributeProvider,
		visibleRangeProvider: @escaping () -> NSRange,
		defaultAttributesProvider: @escaping () -> [NSAttributedString.Key : Any]
	) {
		self.textStorage = textStorage
		self.attributeProvider = attributeProvider
		self.visibleRangeProvider = visibleRangeProvider
		self.defaultAttributesProvider = defaultAttributesProvider
	}

	public init(textView: TextView, attributeProvider: @escaping TokenAttributeProvider) {
		self.textStorage = textView.textStorage
		self.visibleRangeProvider = { textView.visibleTextRange }
		self.attributeProvider = attributeProvider
		self.defaultAttributesProvider = { textView.typingAttributes }
	}
}

extension TextStorageSystemInterface: TextSystemInterface {
	private func setAttributes(_ attrs: [NSAttributedString.Key : Any], in range: NSRange) {
		let clampedRange = range.clamped(to: length)

		textStorage?.setAttributes(attrs, range: clampedRange)
	}

	public func clearStyle(in range: NSRange) {
		setAttributes(defaultAttributesProvider(), in: range)
	}

	public func applyStyle(to token: Token) {
		let attrs = attributeProvider(token)

		setAttributes(attrs, in: token.range)
	}

	public var length: Int {
		textStorage?.length ?? 0
	}

	public var visibleRange: NSRange {
		visibleRangeProvider()
	}
}
