import Foundation
import Rearrange

public class Highlighter {
    public var textInterface: TextSystemInterface

    private var validSet: IndexSet
    private var pendingSet: IndexSet
    public var tokenProvider: TokenProvider

	/// Requests to the TokenProvider will not exceed this length.
	public var requestLengthLimit = 1024

	/// Highlighting may be done past the visible range by up to this amount.
	public var visibleLookAheadLength = 1024

	/// Highlighting may be done before the visible range by up to this amount.
	public var visibleLookBehindLength = 1024

    public init(textInterface: TextSystemInterface, tokenProvider: TokenProvider? = nil) {
        self.textInterface = textInterface
        self.validSet = IndexSet()
        self.pendingSet = IndexSet()
        self.tokenProvider = tokenProvider ?? { _, block in block(.success([]))}
    }
}

extension Highlighter {
    public func invalidate(_ target: TextTarget = .all) {
        preconditionOnMainQueue()

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

	/// Computes the next contiguous invalid range
    private func nextNeededTokenRange() -> NSRange? {
		let visibleRange = visibleTextRange

		let lookBehindLength = requestLengthLimit
		let lookAheadLength = requestLengthLimit

		// expand the visible range by the maximum possible request length
		let expandedVisibleStart = max(visibleRange.location - lookBehindLength, 0)
		let expandedVisibleEnd = min(visibleRange.max + lookAheadLength, textLength)

		let expandedVisibleSet = IndexSet(integersIn: NSRange(expandedVisibleStart..<expandedVisibleEnd))

		// determine what parts of that set are actually invalid
		let expandedVisibleInvalidSet = invalidSet.intersection(expandedVisibleSet)

		// here's a trick. Create a set with a single range, and then remove
		// any pending ranges from it. The result can be used to determine the longest
		// ranges that do not overlap pending.
		let spanSet = expandedVisibleInvalidSet
			.limitSpanningRange
			.map({ IndexSet(integersIn: $0) }) ?? IndexSet()

		let candidateSet = spanSet.subtracting(pendingSet)

		// We want to prioritize the invalid ranges that are actually visible
		let hasVisibleInvalidRanges = visibleSet.intersection(invalidSet).isEmpty == false

		// now get back the first range, which is the longest continuous
		// range that includes invalid regions
		let range = candidateSet.nsRangeView.first{ range in
			guard hasVisibleInvalidRanges else { return true }

			return range.max > visibleRange.location
		}

		guard let range = range else { return nil }

		// make sure to respect the request limit
		return NSRange(location: range.location,
					   length: min(range.length, requestLengthLimit))
    }

    private func makeNextTokenRequest() {
        guard let range = nextNeededTokenRange() else { return }

        self.pendingSet.insert(range: range)

        // this can be called 0 or more times
        tokenProvider(range) { result in
            preconditionOnMainQueue()
            
            switch result {
            case .failure(let error):
                print("failed to get tokens: ", error)

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

		var receivedSet = IndexSet(integersIn: tokenApplication.range ?? range)

        let tokenRanges = tokenApplication.tokens.map({ $0.range })

        receivedSet.insert(ranges: tokenRanges)

        textInterface.apply(tokenApplication, to: receivedSet)

        validSet.formUnion(receivedSet)
    }
}
