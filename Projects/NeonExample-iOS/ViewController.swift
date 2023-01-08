import UIKit
import TreeSitterSwift
import SwiftTreeSitter
import Neon

final class ViewController: UIViewController {
	let textView = UITextView()

	lazy var highlighter: TextViewHighlighter = {
		let language = Language(language: tree_sitter_swift())

		let url = Bundle.main
					  .resourceURL?
					  .appendingPathComponent("TreeSitterSwift_TreeSitterSwift.bundle")
					  .appendingPathComponent("queries/highlights.scm")
		let query = try! language.query(contentsOf: url!)

		let attrProvider: TextViewSystemInterface.AttributeProvider = { token in
			guard token.name.hasPrefix("keyword") else { return [:] }

			return [.foregroundColor: UIColor.red]
		}

		return try! TextViewHighlighter(textView: textView,
										language: language,
										highlightQuery: query,
										attributeProvider: attrProvider)
	}()

	override func viewDidLoad() {
		super.viewDidLoad()

		_ = highlighter.textView

		textView.text = "var something = String()"

		self.view.addSubview(textView)
		textView.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			textView.leftAnchor.constraint(equalTo: view.leftAnchor),
			textView.rightAnchor.constraint(equalTo: view.rightAnchor),
		])
	}
}

