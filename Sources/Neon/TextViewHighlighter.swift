import Foundation
import TreeSitterClient
import SwiftTreeSitter
#if os(macOS)
import AppKit

public enum TextViewHighlighterError: Error {
	case noTextContainer
	case noTextStorage
}

@available(macOS 10.11, *)
public final class TextViewHighlighter: NSObject {
	public let textView: NSTextView
	private let highlighter: Highlighter
	private let treeSitterClient: TreeSitterClient

	public init(textView: NSTextView, client: TreeSitterClient, highlightQuery: Query, attributeProvider: @escaping TextContainerSystemInterface.AttributeProvider) throws {
		self.treeSitterClient = client
		self.textView = textView

		guard let storage = textView.textStorage else { throw TextViewHighlighterError.noTextStorage }

		let textProvider: TreeSitterClient.TextProvider = { range, _ in
			return storage.attributedSubstring(from: range).string
		}

		let tokenProvider = client.tokenProvider(with: highlightQuery, textProvider: textProvider)

		guard let container = textView.textContainer else { throw TextViewHighlighterError.noTextContainer }

		let interface = TextContainerSystemInterface(textContainer: container, attributeProvider: attributeProvider)
		self.highlighter = Highlighter(textInterface: interface, tokenProvider: tokenProvider)

		super.init()

		storage.delegate = self

		guard let scrollView = textView.enclosingScrollView else { return }

		NotificationCenter.default.addObserver(self,
											   selector: #selector(visibleContentChanged(_:)),
											   name: NSView.frameDidChangeNotification,
											   object: scrollView)

		NotificationCenter.default.addObserver(self,
											   selector: #selector(visibleContentChanged(_:)),
											   name: NSView.boundsDidChangeNotification,
											   object: scrollView.contentView)

		treeSitterClient.invalidationHandler = { [weak self] in self?.handleInvalidation($0) }
	}

	public convenience init(textView: NSTextView, language: Language, highlightQuery: Query, attributeProvider: @escaping TextContainerSystemInterface.AttributeProvider) throws {
		let client = try TreeSitterClient(language: language, transformer: { _ in return .zero })

		try self.init(textView: textView, client: client, highlightQuery: highlightQuery, attributeProvider: attributeProvider)
	}

	@objc private func visibleContentChanged(_ notification: NSNotification) {
		highlighter.visibleContentDidChange()
	}

	private func handleInvalidation(_ set: IndexSet) {
		// here is where an HighlightInvalidationBuffer could be handy. Unfortunately,
		// a stock NSTextStorage/NSLayoutManager does not have sufficient callbacks
		// to know when it is safe to mutate the text style.
		DispatchQueue.main.async {
			self.highlighter.invalidate(.set(set))
		}
	}
}

@available(macOS 10.11, *)
extension TextViewHighlighter: NSTextStorageDelegate {

	public func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
		treeSitterClient.willChangeContent(in: editedRange)
	}

	public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
		let adjustedRange = NSRange(location: editedRange.location, length: editedRange.length - delta)

		highlighter.didChangeContent(in: adjustedRange, delta: delta)
		treeSitterClient.didChangeContent(to: textStorage.string, in: adjustedRange, delta: delta, limit: textStorage.string.count)
	}
}

#endif
