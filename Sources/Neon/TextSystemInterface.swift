import Foundation

public protocol TextSystemInterface {
    func clearStyle(in range: NSRange)
    func applyStyle(to token: Token)

    var length: Int { get }
    var visibleRange: NSRange { get }
}

public extension TextSystemInterface {
    func clearStyles(in set: IndexSet) {
        for range in set.nsRangeView {
            clearStyle(in: range)
        }
    }

    func applyStyles(to tokens: [Token]) {
        for token in tokens {
            applyStyle(to: token)
        }
    }

    func apply(_ tokenApplication: TokenApplication, to set: IndexSet) {
        if tokenApplication.action == .replace {
            clearStyles(in: set)
        }

        applyStyles(to: tokenApplication.tokens)
    }
}
