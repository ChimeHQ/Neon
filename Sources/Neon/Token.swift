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
