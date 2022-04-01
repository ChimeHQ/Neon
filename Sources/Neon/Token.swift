import Foundation

public typealias TokenProvider = (NSRange, @escaping (Result<[Token], Error>) -> Void) -> Void

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
