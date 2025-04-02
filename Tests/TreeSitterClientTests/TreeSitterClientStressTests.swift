import Foundation
import Testing

import SwiftTreeSitter
import TreeSitterClient
import NeonTestsTreeSitterSwift

struct TreeSitterClientStressTests {
	@MainActor
	@Test func asyncQueriesWhileRapidlyInserting() async throws {
		let language = Language(tree_sitter_swift())
		
		let queryText = """
("func" @a)
"""
		let query = try Query(language: language, data: Data(queryText.utf8))

		let languageConfig = LanguageConfiguration(
			tree_sitter_swift(),
			name: "Swift",
			queries: [.highlights: query]
		)
		
		let sourceFragment = """
func main() {
  print("hello!")
}

"""
		let insertFragment = String(repeating: sourceFragment, count: 100)
		// this is currently the hard-coded value required to kick BackgroundingLanguageLayerTree into background processing mode
		#expect(insertFragment.utf16.count > 2048)

		var source = sourceFragment

		let clientConfig = TreeSitterClient.Configuration(
			languageProvider: { _ in nil },
			contentSnapshopProvider: { _ in .init(string: source) },
			lengthProvider: { source.utf16.count },
			invalidationHandler: { _ in },
			locationTransformer: { _ in nil }
		)

		let client = try TreeSitterClient(
			rootLanguageConfig: languageConfig,
			configuration: clientConfig
		)

		let iterations = 1000
		
		let mutationTask = Task {
			for _ in 0..<iterations {
				let length = source.utf16.count
				
				source += insertFragment
				
				let range = NSRange(length..<length)
				let delta = insertFragment.utf16.count
				client.didChangeContent(in: range, delta: delta)
				
				await Task.yield()
			}
			
			// and then delete everything
			let length = source.utf16.count
			source = ""
			let range = NSRange(0..<length)
			client.didChangeContent(in: range, delta: -length)
		}
		
		let queryTask = Task {
			let provider = source.predicateTextProvider
			
			for _ in 0..<iterations {
				let length = source.utf16.count
				let start = (0..<length).randomElement() ?? 0
				let end = (start..<length).randomElement() ?? 0
				let clampedEnd = min(end, start + 1024 * 10)
				let range = NSRange(start..<clampedEnd)
				
				_ = try? await client.highlights(in: range, provider: provider, mode: .optional)
			}
		}
		
		await mutationTask.value
		await queryTask.value
	}
}
