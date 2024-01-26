import Foundation

import RangeState
import SwiftTreeSitter
import SwiftTreeSitterLayer
import TreeSitterClient

extension TokenApplication {
	public init(namedRanges: [NamedRange], nameMap: [String : String], range: NSRange) {
		let tokens = namedRanges.map {
			let name = nameMap[$0.name] ?? $0.name

			return Token(name: name, range: $0.range)
		}

		self.init(tokens: tokens, range: range)
	}
}

extension TreeSitterClient {
	@MainActor
	public func tokenProvider(with provider: @escaping TextProvider, nameMap: [String : String] = [:]) -> TokenProvider {
		TokenProvider(
			syncValue: { [highlightsProvider] range in
				do {
					guard let namedRanges = try highlightsProvider.sync(.init(range: range, textProvider: provider)) else {
						return nil
					}

					return TokenApplication(namedRanges: namedRanges, nameMap: nameMap, range: range)
				} catch {
					return []
				}
			},
			mainActorAsyncValue: { [highlightsProvider] range in
				do {
					let namedRanges = try await highlightsProvider.mainActorAsync(.init(range: range, textProvider: provider))

					return TokenApplication(namedRanges: namedRanges, nameMap: nameMap, range: range)
				} catch {
					return []
				}
			}
		)
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

#if os(macOS) || os(iOS) || os(visionOS)
extension TextViewSystemInterface {
	func languageLayerContent(with limit: Int) -> LanguageLayer.Content {
		LanguageLayer.Content(string: textStorage.string, limit: limit)
	}
}
#endif
