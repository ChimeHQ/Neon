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
					let params = TreeSitterClient.ClientQueryParams(range: range, textProvider: provider)
					guard let namedRanges = try highlightsProvider.sync(params) else {
						return nil
					}

					return TokenApplication(namedRanges: namedRanges, nameMap: nameMap, range: range)
				} catch {
					return .noChange
				}
			},
			mainActorAsyncValue: { [highlightsProvider] range in
				do {
					let params = TreeSitterClient.ClientQueryParams(range: range, textProvider: provider)
					let namedRanges = try await highlightsProvider.async(params)

					return TokenApplication(namedRanges: namedRanges, nameMap: nameMap, range: range)
				} catch {
					return .noChange
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

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension TreeSitterClient {
	/// Highlight an input string.
	public static func highlight(
		string: String,
		attributeProvider: TokenAttributeProvider,
		rootLanguageConfig: LanguageConfiguration,
		languageProvider: @escaping LanguageLayer.LanguageProvider
	) async throws -> AttributedString {
		let content = LanguageLayer.Content(string: string)
		let length = string.utf16.count

		let client = try TreeSitterClient(
			rootLanguageConfig: rootLanguageConfig,
			configuration: Configuration(
				languageProvider: languageProvider,
				contentProvider: { _ in content },
				lengthProvider: { length },
				invalidationHandler: { _ in },
				locationTransformer: { _ in nil }
			)
		)

		client.didChangeContent(in: NSRange(0..<0), delta: length)

		let ranges = try await client.highlights(in: NSRange(0..<length), provider: content.textProvider)

		var attributedString = AttributedString(stringLiteral: string)

		for range in ranges {
			let token = Token(name: range.name, range: range.range)
			let attrs = attributeProvider(token)
			guard let strRange = Range<AttributedString.Index>(token.range, in: attributedString) else { continue }

			attributedString[strRange].foregroundColor = attrs[.foregroundColor] as? PlatformColor
		}

		return attributedString
	}
}
#endif
