import Foundation

public final class HighlighterInvalidationBuffer {
    private enum State: Hashable {
        case idle
        case buffering
        case pendingInvalidation(IndexSet)
    }

    private var state: State
    public let highlighter: Highlighter

    public init(highlighter: Highlighter) {
        self.state = .idle
        self.highlighter = highlighter
    }

    public func invalidate(_ target: TextTarget = .all) {
        let set = target.indexSet(with: highlighter.fullTextSet)

        switch state {
        case .idle:
            highlighter.invalidate(target)
        case .buffering:
            self.state = .pendingInvalidation(set)
        case .pendingInvalidation(let oldSet):
            let newSet = set.union(oldSet)

            self.state = .pendingInvalidation(newSet)
        }
    }
}

extension HighlighterInvalidationBuffer {
    public func begin() {
        precondition(self.state == .idle)

        self.state = .buffering
    }

    public func end() {
        switch state {
        case .pendingInvalidation(let set):
            self.state = .idle
            highlighter.invalidate(.set(set))
        case .buffering:
            self.state = .idle
        case .idle:
            preconditionFailure()
        }
    }
}
