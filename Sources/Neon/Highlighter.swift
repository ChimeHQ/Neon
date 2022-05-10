import Foundation
import Rearrange
import os.log

public enum TextTarget {
    case set(IndexSet)
    case range(NSRange)
    case all

    public func indexSet(with fullSet: IndexSet) -> IndexSet {
        let set: IndexSet

        switch self {
        case .set(let indexSet):
            set = indexSet
        case .range(let range):
            set = IndexSet(integersIn: range)
        case .all:
            set = fullSet
        }

        return set
    }
}

public class Highlighter {
    public var textInterface: TextSystemInterface

    private var validSet: IndexSet
    private var pendingSet: IndexSet
    private var log: OSLog
    public var tokenProvider: TokenProvider

    public init(textInterface: TextSystemInterface, tokenProvider: TokenProvider? = nil) {
        self.textInterface = textInterface
        self.validSet = IndexSet()
        self.pendingSet = IndexSet()
        self.tokenProvider = tokenProvider ?? { _, block in block(.success([]))}

        self.log = OSLog(subsystem: "com.chimehq.Neon", category: "Highlighter")
    }
}

extension Highlighter {
    public func invalidate(_ target: TextTarget = .all) {
        dispatchPrecondition(condition: .onQueue(.main))

        let set = target.indexSet(with: fullTextSet)

        if set.isEmpty {
            return
        }

        validSet.subtract(set)
        pendingSet.subtract(set)

        makeNextTokenRequest()
    }
}

extension Highlighter {
    /// Calculates any newly-visible text that is invalid
    ///
    /// You should invoke this method when the visible text
    /// in your system changes.
    public func visibleContentDidChange() {
        let set = invalidSet.intersection(visibleSet)

        invalidate(.set(set))
    }

    /// Update internal state in response to an edit.
    ///
    /// This method must be invoked on every text change. The `range`
    /// parameter must refer to the range of text that **was** changed.
    /// Consider the example text `"abc"`.
    ///
    /// Inserting a "d" at the end:
    ///
    ///     range = NSRange(3..<3)
    ///     delta = 1
    ///
    /// Deleting the middle "b":
    ///
    ///     range = NSRange(1..<2)
    ///     delta = -1
    public func didChangeContent(in range: NSRange, delta: Int) {
        let limit = textLength - delta

        let mutation = RangeMutation(range: range, delta: delta, limit: limit)

        self.validSet = mutation.transform(set: validSet)

        if pendingSet.isEmpty {
            return
        }

        // if we have pending requests, we have to start over
        self.pendingSet.removeAll()
        DispatchQueue.main.async {
            self.makeNextTokenRequest()
        }
    }
}

extension Highlighter {
    private var visibleTextRange: NSRange {
        return textInterface.visibleRange
    }

    private var textLength: Int {
        return textInterface.length
    }

    var fullTextSet: IndexSet {
        return IndexSet(integersIn: 0..<textLength)
    }

    private var visibleSet: IndexSet {
        return IndexSet(integersIn: visibleTextRange)
    }

    private var invalidSet: IndexSet {
        return fullTextSet.subtracting(validSet)
    }

    private func nextNeededTokenRange() -> NSRange? {
        // first, compute the set that is actually visible, invalid, and
        // not yet requested
        let candidateSet = invalidSet
            .intersection(visibleSet)
            .subtracting(pendingSet)

        guard let range = candidateSet.nsRangeView.first else { return nil }

        // what we want to do now is expand that range to
        // cover as much adjacent invalid area as possible
        // within a limit
        let maxLength = 1024
        let amount = max(0, maxLength - range.length)
        let start = max(0, range.location - amount / 2)
        let end  = min(textLength, range.max + amount / 2)

        let expanded = NSRange(start..<end)

        // we now need to re-restrict this new range by what's actually invalid and pending
        let set = IndexSet(integersIn: expanded)
            .intersection(invalidSet)
            .subtracting(pendingSet)

        return set.nsRangeView.first
    }

    private func makeNextTokenRequest() {
        guard let range = nextNeededTokenRange() else { return }

        self.pendingSet.insert(range: range)

        // this can be called 0 or more times
        tokenProvider(range) { result in
            dispatchPrecondition(condition: .onQueue(.main))
            
            switch result {
            case .failure(let error):
                os_log("failed to get tokens: %{public}@", log: self.log, type: .error, String(describing: error))

                DispatchQueue.main.async {
                    self.pendingSet.remove(integersIn: range)
                }
            case .success(let tokens):
                self.handleTokens(tokens, for: range)

                DispatchQueue.main.async {
                    self.makeNextTokenRequest()
                }
            }
        }

    }
}

extension Highlighter {
    private func handleTokens(_ tokenApplication: TokenApplication, for range: NSRange) {
        self.pendingSet.remove(integersIn: range)

        var receivedSet = IndexSet(integersIn: range)

        let tokenRanges = tokenApplication.tokens.map({ $0.range })

        receivedSet.insert(ranges: tokenRanges)

        textInterface.apply(tokenApplication, to: receivedSet)

        validSet.formUnion(receivedSet)
    }
}
