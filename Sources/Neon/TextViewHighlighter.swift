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
/// This class is a minimal implementation that can help perform highlighting for a TextView. It is compatible with both TextKit 1 and 2 views, and uses single-phase pass with tree-sitter. The created instance will become the delegate of the view's `NSTextStorage`.
@MainActor
@preconcurrency
public final class TextViewHighlighter {
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
	private let storageDelegate = TextStorageDelegate()

#if os(iOS) || os(visionOS)
	private var frameObservation: NSKeyValueObservation?
	private var lastVisibleRange = NSRange.zero
#endif

	/// Create a instance.
	///
	/// This method will also invoke `observeEnclosingScrollView` if `textView` is within a scroll view. If not, you can invoke it directly after the view has been placed into a scroll view.
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
				contentSnapshopProvider: { [interface] in interface.languageLayerContentSnapshot(with: $0) },
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

		buffer.invalidationHandler = { [styler] in
			styler.invalidate($0)

			styler.validate()
		}

		storageDelegate.willChangeContent = { [buffer, client] range, _ in
			// a change happening, start buffering invalidations
			buffer.beginBuffering()

			client.willChangeContent(in: range)
		}

		storageDelegate.didChangeContent = { [buffer, client, styler] range, delta in
			let adjustedRange = NSRange(location: range.location, length: range.length - delta)

			client.didChangeContent(in: adjustedRange, delta: delta)
			styler.didChangeContent(in: adjustedRange, delta: delta)

			// At this point in mutation processing, it is unsafe to apply style changes. Ideally, we'd have a hook so we can know when it is ok. But, no such system exists for stock TextKit 1/2. So, instead we just let the runloop turn. This is *probably* safe, if the text does not change again, but can also result in flicker.
			DispatchQueue.main.async {
				buffer.endBuffering()
			}

		}

		try textView.getTextStorage().delegate = storageDelegate

		observeEnclosingScrollView()

		invalidate(.all)
	}

	/// Perform manual invalidation on the underlying highlighter
	public func invalidate(_ target: RangeTarget) {
		buffer.invalidate(target)
	}

	/// Inform the client that calls to languageConfiguration may change.
	public func languageConfigurationChanged(for name: String) {
		client.languageConfigurationChanged(for: name)
	}
}

extension TextViewHighlighter {
	/// Begin monitoring for containing scroll view changes.
	///
	/// This method sets up all the necessary monitoring so the highlighter can react to scrolling. It should be called only once the view heirarchy is fully established.
	public func observeEnclosingScrollView() {
#if os(macOS) && !targetEnvironment(macCatalyst)
		guard let scrollView = textView.enclosingScrollView else {
			print("warning: there is no enclosing scroll view")
			return
		}
		
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(visibleContentChanged(_:)),
			name: NSView.frameDidChangeNotification,
			object: scrollView
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(visibleContentChanged(_:)),
			name: NSView.boundsDidChangeNotification,
			object: scrollView.contentView
		)
#elseif os(iOS) || os(visionOS)
		self.frameObservation = textView.observe(\.contentOffset) { [weak self] view, _ in
			MainActor.assumeIsolated {
				guard let self = self else { return }

				self.lastVisibleRange = self.textView.visibleTextRange

				DispatchQueue.main.async {
					guard self.textView.visibleTextRange == self.lastVisibleRange else { return }

					self.styler.validate(.range(self.lastVisibleRange))
				}
			}
		}
#endif
	}

	@objc private func visibleContentChanged(_ notification: NSNotification) {
		let visibleRange = textView.visibleTextRange

		styler.validate(.range(visibleRange))
	}
}

#endif
