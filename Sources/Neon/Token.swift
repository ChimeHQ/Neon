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
        case merge
    }

    public let tokens: [Token]
    public let action: Action

    public init(tokens: [Token], action: TokenApplication.Action = .replace) {
        self.tokens = tokens
        self.action = action
    }
}

extension TokenApplication: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = Token

    public init(arrayLiteral elements: Token...) {
        self.init(tokens: elements)
    }
}

public typealias TokenProvider = (NSRange, @escaping (Result<TokenApplication, Error>) -> Void) -> Void
