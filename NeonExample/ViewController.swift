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
		
		let provider: TextViewSystemInterface.AttributeProvider = { token in
			guard token.name.hasPrefix("keyword") else { return [:] }

			return [NSAttributedString.Key.foregroundColor: NSColor.red]
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
		textView.string = "let value = \"hello world\"\nprint(value)"
	}
}
