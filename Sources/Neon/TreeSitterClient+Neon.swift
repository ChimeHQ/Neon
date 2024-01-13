import Foundation

import RangeState
import SwiftTreeSitter
import SwiftTreeSitterLayer
import TreeSitterClient

extension TreeSitterClient {
	public func tokenProvider(with provider: @escaping TextProvider) -> TokenProvider {
		HybridValueProvider<NSRange, [NamedRange]>(
			syncValue: { [highlightsProvider] range in
				do {
					return try highlightsProvider.sync(.init(range: range, textProvider: provider))
				} catch {
					return []
				}
			},
			asyncValue: { [highlightsProvider] range in
				do {
					return try await highlightsProvider.async(.init(range: range, textProvider: provider))
				} catch {
					return []
				}
			}
		).map { namedRanges in
			TokenApplication(tokens: namedRanges.map({ Token(name: $0.name, range: $0.range) }))
		}
	}
}

extension LanguageLayer.Content {
	/// this should probably move into SwiftTreeSitterLayer
	init(string: String, limit: Int) {
		let read = Parser.readFunction(for: string, limit: limit)

		self.init(
			readHandler: read,
			textProvider: string.predicateTextProvider
		)
	}
}

extension TextViewSystemInterface {
	func languageLayerContent(with limit: Int) -> LanguageLayer.Content {
		LanguageLayer.Content(string: textStorage.string, limit: limit)
	}
}
