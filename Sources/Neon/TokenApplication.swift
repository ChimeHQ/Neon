import Foundation

public struct TokenApplication {
    public enum Action {
        case replace
        case apply
    }

    public let tokens: [Token]
	public let range: NSRange?
    public let action: Action

	public init(tokens: [Token], range: NSRange? = nil, action: TokenApplication.Action = .replace) {
        self.tokens = tokens
		self.range = range
        self.action = action
    }

    public static let noChange = TokenApplication(tokens: [], action: .apply)
}

extension TokenApplication: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = Token

    public init(arrayLiteral elements: Token...) {
        self.init(tokens: elements)
    }
}

/// A source of `Token` information
///
/// This is a function that takes a target range to be styled and invokes
/// the callback with token data. The callback argument is a little special,
/// so here are some things to keep in mind:
///
/// - It must be invoked on the main queue.
/// - Its argument applies to the entire range parameter.
/// - It is safe to invoke 0 or more times.
/// - Minimizing the number of invocations will improve efficiency.
/// - Failures are always assumed to be transient.
public typealias TokenProvider = (NSRange, @escaping (Result<TokenApplication, Error>) -> Void) -> Void
