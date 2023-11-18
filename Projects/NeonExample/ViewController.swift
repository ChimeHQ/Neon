import Cocoa
import Neon
import SwiftTreeSitter
import TreeSitterSwift

final class ViewController: NSViewController {
	let textView: NSTextView
	let scrollView = NSScrollView()
	let highlighter: TextViewHighlighter

	init() {
		self.textView = NSTextView()

		scrollView.documentView = textView
		
		let regularFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
		let boldFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .bold)
		let italicFont = NSFont(descriptor: regularFont.fontDescriptor.withSymbolicTraits(.italic), size: 16) ?? regularFont

		// Alternatively, set `textView.typingAttributes = [.font: regularFont, ...]`
		// if you want to customize other default (fallback) attributes.
		textView.font = regularFont

		let provider: TextViewSystemInterface.AttributeProvider = { token in
			return switch token.name {
			case let keyword where keyword.hasPrefix("keyword"): [.foregroundColor: NSColor.red, .font: boldFont]
			case "comment": [.foregroundColor: NSColor.green, .font: italicFont]
			default: [.foregroundColor: NSColor.textColor, .font: regularFont]
			}
		}

		let language = Language(language: tree_sitter_swift())

		let url = Bundle.main
					  .resourceURL?
					  .appendingPathComponent("TreeSitterSwift_TreeSitterSwift.bundle")
					  .appendingPathComponent("Contents/Resources/queries/highlights.scm")
		let query = try! language.query(contentsOf: url!)

		self.highlighter = try! TextViewHighlighter(textView: textView,
													language: language,
													highlightQuery: query,
													attributeProvider: provider)

		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		let max = CGFloat.greatestFiniteMagnitude

		textView.minSize = NSSize.zero
		textView.maxSize = NSSize(width: max, height: max)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = true

		self.view = scrollView
	}

	override func viewWillAppear() {
		textView.string = """
		// Example Code!
		let value = "hello world"
		print(value)
		"""
	}
}
