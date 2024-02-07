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
	public enum Action: Sendable, Hashable {
		case replace
		case apply
	}

	public let tokens: [Token]
	public let range: NSRange?
	public let action: Action

	public init(tokens: [Token], range: NSRange? = nil, action: Action = .replace) {
		self.tokens = tokens
		self.range = range
		self.action = action
	}

	public static let noChange = TokenApplication(tokens: [], action: .apply)
}

public typealias TokenProvider = HybridValueProvider<NSRange, TokenApplication>

extension TokenProvider {
	/// A TokenProvider that returns an empty set of tokens for all requests.
	public static var none: TokenProvider {
		.init(
			syncValue: { _ in
				return .noChange
			},
			asyncValue: { _, _ in
				return .noChange
			}
		)
	}
}
