import Foundation

import RangeState

#if os(macOS)
import AppKit

public typealias TextView = NSTextView
typealias PlatformColor = NSColor
#elseif os(iOS) || os(visionOS) || os(tvOS)
import UIKit

public typealias TextView = UITextView
typealias PlatformColor = UIColor
#endif

#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
extension NSTextStorage: VersionedContent {
	public var currentVersion: Int {
		let value = hashValue

		return value
	}

	public func length(for version: Int) -> Int? {
		guard version == currentVersion else { return nil }

		return length
	}
}

@available(macOS 12.0, iOS 16.0, tvOS 16.0, *)
extension NSTextContentManager: VersionedContent {
	public var currentVersion: Int {
		hashValue
	}

	public func length(for version: Int) -> Int? {
		guard version == currentVersion else { return nil }

		return NSRange(documentRange, provider: self).length
	}
}

extension NSTextContainer {
	func textRange(for rect: CGRect) -> NSRange? {
		if #available(macOS 12.0, iOS 15.0, tvOS 15.0, *), textLayoutManager != nil {
			return nil
		}
		
		guard let layoutManager = self.layoutManager else { return nil }

		let glyphRange = layoutManager.glyphRange(forBoundingRect: rect, in: self)

		return layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
	}
}

extension TextView {
	var tk2VisibleTextRange: NSRange? {
		guard
			#available(macOS 12.0, iOS 16.0, tvOS 16.0, *),
			let textLayoutManager,
			let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange,
			let textContentManager = textLayoutManager.textContentManager
		else {
			return nil
		}

		return NSRange(viewportRange, provider: textContentManager)
	}

	var tk1VisibleTextRange: NSRange? {
#if os(macOS) && !targetEnvironment(macCatalyst)
		let length = self.textStorage?.length ?? 0

		let origin = textContainerOrigin
		let offsetRect = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)

		return textContainer?.textRange(for: offsetRect) ?? NSRange(0..<length)
#elseif os(iOS) || os(visionOS) || os(tvOS)
		let visibleRect = CGRect(origin: contentOffset, size: bounds.size)

		return textContainer.textRange(for: visibleRect)
#endif
	}

	public var visibleTextRange: NSRange {
		tk2VisibleTextRange ?? tk1VisibleTextRange ?? .zero
	}
}

#endif
