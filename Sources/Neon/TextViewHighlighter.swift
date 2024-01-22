import Foundation

import RangeState
import TreeSitterClient
import SwiftTreeSitter
import SwiftTreeSitterLayer

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

#if os(macOS) || os(iOS) || os(visionOS)
public enum TextViewHighlighterError: Error {
	case noTextStorage
}

extension TextView {
#if os(macOS) && !targetEnvironment(macCatalyst)
	func getTextStorage() throws -> NSTextStorage {
		guard let storage = textStorage else {
			throw TextViewHighlighterError.noTextStorage
		}

		return storage
	}
#else
	func getTextStorage() throws -> NSTextStorage {
		textStorage
	}
#endif
}

/// A class that can connect `NSTextView`/`UITextView` to `TreeSitterClient`
///
/// This class is a minimal implementation that can help perform highlighting
/// for a TextView. The created instance will become the delegate of the
/// view's `NSTextStorage`.
@MainActor
public final class TextViewHighlighter: NSObject {
	private typealias Styler = TextSystemStyler<TextViewSystemInterface>

	public struct Configuration {
		public let languageConfiguration: LanguageConfiguration
		public let attributeProvider: TokenAttributeProvider
		public let languageProvider: LanguageLayer.LanguageProvider
		public let locationTransformer: Point.LocationTransformer

		public init(
			languageConfiguration: LanguageConfiguration,
			attributeProvider: @escaping TokenAttributeProvider,
			languageProvider: @escaping LanguageLayer.LanguageProvider = { _ in nil },
			locationTransformer: @escaping Point.LocationTransformer
		) {
			self.languageConfiguration = languageConfiguration
			self.attributeProvider = attributeProvider
			self.languageProvider = languageProvider
			self.locationTransformer = locationTransformer
		}
	}

	public let textView: TextView

	private let configuration: Configuration
	private let styler: Styler
	private let interface: TextViewSystemInterface
	private let client: TreeSitterClient
	private let buffer = RangeInvalidationBuffer()

	public init(
		textView: TextView,
		configuration: Configuration
	) throws {
		self.textView = textView
		self.configuration = configuration
		self.interface = TextViewSystemInterface(textView: textView, attributeProvider: configuration.attributeProvider)
		self.client = try TreeSitterClient(
			rootLanguageConfig: configuration.languageConfiguration,
			configuration: .init(
				languageProvider: configuration.languageProvider,
				contentProvider: { [interface] in interface.languageLayerContent(with: $0) },
				lengthProvider: { [interface] in interface.content.currentLength },
				invalidationHandler: { [buffer] in buffer.invalidate(.set($0)) },
				locationTransformer: configuration.locationTransformer
			)
		)

		// this level of indirection is necessary so when the TextProvider is accessed it always uses the current version of the content
		let tokenProvider = client.tokenProvider(with: { [interface] in
			interface.content.string.predicateTextProvider($0, $1)
		})

		self.styler = TextSystemStyler(
			textSystem: interface,
			tokenProvider: tokenProvider
		)

		super.init()

		buffer.invalidationHandler = { [styler] in styler.invalidate($0) }

		try textView.getTextStorage().delegate = self

#if os(macOS) && !targetEnvironment(macCatalyst)
		guard let scrollView = textView.enclosingScrollView else { return }

		NotificationCenter.default.addObserver(self,
											   selector: #selector(visibleContentChanged(_:)),
											   name: NSView.frameDidChangeNotification,
											   object: scrollView)

		NotificationCenter.default.addObserver(self,
											   selector: #selector(visibleContentChanged(_:)),
											   name: NSView.boundsDidChangeNotification,
											   object: scrollView.contentView)
#endif

		invalidate(.all)
	}

	@objc private func visibleContentChanged(_ notification: NSNotification) {
		styler.visibleContentDidChange()
	}

	/// Perform manual invalidation on the underlying highlighter
	public func invalidate(_ target: RangeTarget) {
		buffer.invalidate(target)
	}
}

extension TextViewHighlighter: NSTextStorageDelegate {
	public nonisolated func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: TextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
		MainActor.backport.assumeIsolated {
			client.willChangeContent(in: editedRange)
		}
	}

	public nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: TextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
		MainActor.backport.assumeIsolated {
			// Avoid potential infinite loop in synchronous highlighting. If attributes
			// are stored in `textStorage`, that applies `.editedAttributes` only.
			// We don't need to re-apply highlighting in that case.
			// (With asynchronous highlighting, it's not blocking, but also never stops.)
			guard editedMask.contains(.editedCharacters) else { return }

			let adjustedRange = NSRange(location: editedRange.location, length: editedRange.length - delta)

			styler.didChangeContent(in: adjustedRange, delta: delta)
			client.didChangeContent(in: adjustedRange, delta: delta)
		}
	}
}

#endif
