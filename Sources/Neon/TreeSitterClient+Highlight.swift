import Foundation
import SwiftTreeSitter
import TreeSitterClient

extension TreeSitterClient {
    public typealias TextProvider = ResolvingQueryCursor.TextProvider

    private func tokensFromCursor(_ cursor: ResolvingQueryCursor, textProvider: TextProvider?) -> [Token] {
        if let textProvider = textProvider {
            cursor.prepare(with: textProvider)
        }

        return cursor
            .map({ $0.captures })
            .flatMap({ $0 })
            .sorted()
            .compactMap { capture -> Token? in
                guard let name = capture.name else { return nil }

                return Token(name: name, range: capture.node.range)
            }
    }

    public func executeHighlightsQuery(_ query: Query,
                                       in range: NSRange,
                                       executionMode: ExecutionMode = .asynchronous(prefetch: true),
                                       textProvider: TextProvider? = nil,
                                       completionHandler: @escaping (Result<[Token], TreeSitterClientError>) -> Void) {
        executeResolvingQuery(query, in: range, executionMode: executionMode) { cursorResult in
            let result = cursorResult.map({ self.tokensFromCursor($0, textProvider: textProvider) })

            completionHandler(result)
        }
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0.0, tvOS 13.0.0, *)
    @MainActor
    public func highlights(with query: Query,
                           in range: NSRange,
                           executionMode: ExecutionMode = .asynchronous(prefetch: true),
                           textProvider: TextProvider? = nil) async throws -> [Token] {
        try await withCheckedThrowingContinuation { continuation in
            self.executeHighlightsQuery(query, in: range, executionMode: executionMode, textProvider: textProvider) { result in
                continuation.resume(with: result)
            }
        }
    }
}

extension TreeSitterClient {
	public func tokenProvider(with query: Query,
							  executionMode: ExecutionMode = .asynchronous(prefetch: true),
							  textProvider: TextProvider? = nil) -> TokenProvider {
		return { [weak self] range, completionHandler in
			guard let self = self else {
				completionHandler(.failure(TreeSitterClientError.stateInvalid))
				return
			}

			self.executeHighlightsQuery(query, in: range, executionMode: executionMode, textProvider: textProvider) { result in
				let tokenApp = result
					.map({ TokenApplication(tokens: $0) })
					.mapError({ $0 as Error })

				completionHandler(tokenApp)
			}
		}
	}
}
