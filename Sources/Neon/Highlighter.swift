import Foundation
import Rearrange
import os.log

public protocol TextSystemInterface {
    func clearStyle(in range: NSRange)
    func applyStyle(to token: Token)

    var length: Int { get }
    var visibleRange: NSRange { get }
}

public class Highlighter {
    public var textInterface: TextSystemInterface

    private var validSet: IndexSet
    private var pendingSet: IndexSet
    private var log: OSLog
    public var tokenProvider: TokenProvider
    private var failed: Bool

    public init(textInterface: TextSystemInterface, tokenProvider: TokenProvider? = nil) {
        self.textInterface = textInterface
        self.validSet = IndexSet()
        self.pendingSet = IndexSet()
        self.tokenProvider = tokenProvider ?? { _, block in block(.success([]))}
        self.failed = false

        self.log = OSLog(subsystem: "com.chimehq.Neon", category: "Highlighter")
    }
}

extension Highlighter {
    public func invalidate(_ set: IndexSet) {
        dispatchPrecondition(condition: .onQueue(.main))

        self.failed = false
        validSet.subtract(set)
        pendingSet.subtract(set)

        makeNextTokenRequest()
    }

    public func invalidate(_ range: NSRange) {
        invalidate(IndexSet(integersIn: range))
    }

    public func invalidate() {
        invalidate(fullTextSet)
    }
}

extension Highlighter {
    public func visibleContentDidChange() {
        let set = invalidSet.intersection(visibleSet)

        invalidate(set)
    }

    public func didChangeContent(in range: NSRange, delta: Int, limit: Int) {
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
        guard failed == false else { return }

        guard let range = nextNeededTokenRange() else { return }

        self.pendingSet.insert(range: range)

        tokenProvider(range) { result in
            switch result {
            case .failure(let error):
                os_log("failed to get tokens: %{public}@", log: self.log, type: .error, String(describing: error))

                DispatchQueue.main.async {
                    self.failed = true
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

        let receivedSet = IndexSet(integersIn: range)

        applyStyle(with: tokenApplication, in: receivedSet)
    }

    private func applyStyle(with tokenApplication: TokenApplication, in set: IndexSet) {
        precondition(set.isEmpty == false)

        if tokenApplication.action == .replace {
            for range in set.nsRangeView {
                textInterface.clearStyle(in: range)
            }
        }

        for token in tokenApplication.tokens {
            textInterface.applyStyle(to: token)
        }

        validSet.formUnion(set)
    }
}
