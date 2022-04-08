import Foundation

public struct Token {
    public let name: String
    public let range: NSRange

    public init(name: String, range: NSRange) {
        self.name = name
        self.range = range
    }
}

extension Token: Hashable {
}

public struct TokenApplication {
    public enum Action {
        case replace
        case apply
    }

    public let tokens: [Token]
    public let action: Action

    public init(tokens: [Token], action: TokenApplication.Action = .replace) {
        self.tokens = tokens
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
/// The callback argument of this function is a little funny. It is ok
/// to invoke it 0 to N times. Always invoke it on the main queue.
///
/// Note: failures are always assumed to be transient. The
/// best way to indicate a permenant failure is to just return
/// `TokenApplication.noChange`.
public typealias TokenProvider = (NSRange, @escaping (Result<TokenApplication, Error>) -> Void) -> Void
