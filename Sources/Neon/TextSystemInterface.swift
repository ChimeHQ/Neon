import Foundation

public protocol TextSystemInterface {
	@MainActor
    func clearStyle(in range: NSRange)
	@MainActor
    func applyStyle(to token: Token)

	@MainActor
    var length: Int { get }
	@MainActor
    var visibleRange: NSRange { get }
}

@MainActor
public extension TextSystemInterface {
    func clearStyles(in set: IndexSet) {
        for range in set.nsRangeView {
            clearStyle(in: range)
        }
    }

    func clearAllStyles() {
        clearStyle(in: NSRange(0..<length))
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
