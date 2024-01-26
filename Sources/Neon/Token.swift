import Foundation

import RangeState

public struct Token: Hashable, Sendable {
	public let name: String
	public let range: NSRange

	public init(name: String, range: NSRange) {
		self.name = name
		self.range = range
	}
}

extension Token: CustomDebugStringConvertible {
	public var debugDescription: String {
		"<\"\(name)\": \(range)>"
	}
}

public struct TokenApplication: Hashable, Sendable {
	public let tokens: [Token]
	public let range: NSRange?

	public init(tokens: [Token], range: NSRange? = nil) {
		self.tokens = tokens
		self.range = range
	}
}

extension TokenApplication: ExpressibleByArrayLiteral {
	public typealias ArrayLiteralElement = Token
	
	public init(arrayLiteral elements: Token...) {
		self.init(tokens: elements)
	}
}

public typealias TokenProvider = HybridValueProvider<NSRange, TokenApplication>

extension TokenProvider {
	/// A TokenProvider that returns an empty set of tokens for all requests.
	public static var none: TokenProvider {
		.init(
			syncValue: { _ in
				return TokenApplication(tokens: [])
			},
			asyncValue: { _, _ in
				return TokenApplication(tokens: [])
			}
		)
	}
}
