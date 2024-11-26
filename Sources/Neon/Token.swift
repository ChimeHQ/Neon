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

/// A type that assigns semantic value to a range of text either synchronously or asynchronously.
///
/// The underlying parsing system must be able to translate a request for tokens expressed as an `NSRange` into a `TokenApplication`.
///
/// This would be a lot easier to implement if the interface was purely asynchronous. However, Neon provides a fully synchronous styling path. Avoiding the need for an async context can be very useful, and makes it possible to provide a flicker-free guarantee if the underlying parsing system can process the work required in reasonable time. Your actual implementation, however, does not actually have to implement the synchronous path if that's too difficult.
public typealias TokenProvider = HybridSyncAsyncValueProvider<NSRange, TokenApplication, Never>

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

	/// A TokenProvider that returns an empty set of tokens for all async requests, but fails to resolve tokens synchronously.
	public static var asyncOnlyNone: TokenProvider {
		.init(
			syncValue: { _ in
				return nil
			},
			asyncValue: { _, _ in
				return .noChange
			}
		)
	}
}
