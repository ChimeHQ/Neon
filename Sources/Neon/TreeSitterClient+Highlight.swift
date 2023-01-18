import Foundation
import SwiftTreeSitter
import TreeSitterClient

extension TreeSitterClient {
	/// Produce a `TokenProvider` function for use with `Highlighter`.
	public func tokenProvider(with query: Query,
							  executionMode: ExecutionMode = .asynchronous(prefetch: true),
							  textProvider: TextProvider? = nil) -> TokenProvider {
		return { [weak self] range, completionHandler in
			guard let self = self else {
				completionHandler(.failure(TreeSitterClientError.stateInvalid))
				return
			}

			self.executeHighlightsQuery(query, in: range, executionMode: executionMode, textProvider: textProvider) { result in
				switch result {
				case .failure(let error):
					completionHandler(.failure(error))
				case .success(let namedRanges):
					let tokens = namedRanges.map { Token(name: $0.name, range: $0.range) }
					let tokenApp = TokenApplication(tokens: tokens)

					completionHandler(.success(tokenApp))
				}
			}
		}
	}
}
