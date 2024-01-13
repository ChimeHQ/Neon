import Cocoa
import Neon
import SwiftTreeSitter
import TreeSitterSwift
import TreeSitterClient

final class ViewController: NSViewController {
	let textView: NSTextView
	let scrollView = NSScrollView()
	let highlighter: TextViewHighlighter

	init() {
		self.textView = NSTextView()
		textView.isRichText = false  // Discards any attributes when pasting.

		textView.string = """
		// Example Code!
		let value = "hello world"
		print(value)
		"""
		
		scrollView.documentView = textView
		
		let regularFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
		let boldFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .bold)
		let italicFont = NSFont(descriptor: regularFont.fontDescriptor.withSymbolicTraits(.italic), size: 16) ?? regularFont

		// Set the default styles. This is applied by stock `NSTextStorage`s during
		// so-called "attribute fixing" when you type, and we emulate that as
		// part of the highlighting process in `TextViewSystemInterface`.
		textView.typingAttributes = [
			.foregroundColor: NSColor.darkGray,
			.font: regularFont,
		]

		let provider: TokenAttributeProvider = { token in
			return switch token.name {
			case let keyword where keyword.hasPrefix("keyword"): [.foregroundColor: NSColor.red, .font: boldFont]
			case "comment": [.foregroundColor: NSColor.green, .font: italicFont]
			// Note: Default is not actually applied to unstyled/untokenized text.
			default: [.foregroundColor: NSColor.blue, .font: regularFont]
			}
		}

		let languageConfig = try! LanguageConfiguration(
			tree_sitter_swift(),
			name: "Swift"
		)

		let highlighterConfig = TextViewHighlighter.Configuration(
			languageConfiguration: languageConfig,
			attributeProvider: provider,
			locationTransformer: { _ in nil }
		)

		self.highlighter = try! TextViewHighlighter(textView: textView, configuration: highlighterConfig)

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

	func setUpTreeSitter() throws {
		let languageConfig = try LanguageConfiguration(
			tree_sitter_swift(),
			name: "Swift"
		)

		let clientConfig = TreeSitterClient.Configuration(
			languageProvider: { identifier in
				// look up nested languages by identifier here. If done
				// asynchronously, inform the client they are ready with
				// `languageConfigurationChanged(for:)`
				return nil
			},
			contentProvider: { [textView] length in
				// given a maximum needed length, produce a Content structure
				// that will be used to access the text data

				return .init(string: textView.string)
			},
			lengthProvider: { [textView] in
				textView.string.utf16.count

			},
			invalidationHandler: { set in
				// take action on invalidated regions of the text
			},
			locationTransformer: { location in
				// optionally, use the UTF-16 location to produce a line-relative Point structure.
				return nil
			}
		)

		let client = try TreeSitterClient(
			rootLanguageConfig: languageConfig,
			configuration: clientConfig
		)

		let source = textView.string

		let provider = source.predicateTextProvider

		// this uses the synchronous query API, but with the `.required` mode, which will force the client
		// to do all processing necessary to satsify the request.
		let highlights = try client.highlights(in: NSRange(0..<24), provider: provider, mode: .required)!

		print("highlights:", highlights)
	}
}
