import Foundation

import RangeState

/// A semantic label and range pair.
///
/// This type represents a range of text that has semantic meaning.
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

/// Describes the semantic meaning of a range of text and any style operations that should be applied.
public struct TokenApplication: Hashable, Sendable {
	public enum Action: Sendable, Hashable {
		// Replace any existing styling with this application.
		case replace
		// Apply styling without first removing any existing styles.
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

/// A function that assigns semantic value to a range of text.
///
/// The input will be an `NSRange` representing the text that needs styling, and the output is a `TokenApplication`.
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
