import Foundation
import SwiftTreeSitter
import Rearrange
import OperationPlus

public enum TreeSitterClientError: Error {
    case parseStateNotUpToDate
    case parseStateInvalid
    case unableToTransformRange(NSRange)
    case unableToTransformByteRange(Range<UInt32>)
    case staleContent
}

public final class TreeSitterClient {
    struct ContentEdit {
        var rangeMutation: RangeMutation
        var inputEdit: InputEdit

        var postApplyLimit: Int {
            return rangeMutation.postApplyLimit
        }

        var size: Int {
            return max(abs(rangeMutation.delta), rangeMutation.range.length)
        }

        var affectedRange: NSRange {
            let range = rangeMutation.range

            // deletes make it possible to have no affected range
            let affectedLength = max(range.length, range.length + rangeMutation.delta)

            return NSRange(location: range.location, length: affectedLength).clamped(to: postApplyLimit)
        }
    }
    
    private var oldEndPoint: Point?
    private let parser: Parser
    private var parseState: TreeSitterParseState
    private var outstandingEdits: [ContentEdit]
    private var version: Int
    private let parseQueue: OperationQueue
    private var maximumProcessedLocation: Int

    public let transformer: TreeSitterCoordinateTransformer
    public let synchronousLengthThreshold: Int?
    public var computeInvalidations: Bool

    /// Invoked when parts of the text content have changed
    ///
    /// This function always returns values that represent
    /// the current state of the content, even if the
    /// system is working in the background.
    ///
    /// This function will only be invoked if `computeInvalidations`
    /// was true at the time an edit was applied.
    public var invalidationHandler: (IndexSet) -> Void

    init(language: Language, transformer: TreeSitterCoordinateTransformer, synchronousLengthThreshold: Int? = 1024) throws {
        self.parser = Parser()
        self.parseState = TreeSitterParseState(tree: nil)
        self.outstandingEdits = []
        self.computeInvalidations = true
        self.version = 0
        self.maximumProcessedLocation = 0
        self.parseQueue = OperationQueue.serialQueue(named: "com.chimehq.Neon.TreeSitterClient")

        try parser.setLanguage(language)

        self.invalidationHandler = { _ in }
        self.transformer = transformer
        self.synchronousLengthThreshold = synchronousLengthThreshold
    }

    public convenience init(language: Language, locationToPoint: @escaping (Int) -> Point?) throws {
        let transformer = TreeSitterCoordinateTransformer(locationToPoint: locationToPoint)

        try self.init(language: language, transformer: transformer)
    }

    public var hasQueuedEdits: Bool {
        return outstandingEdits.count > 0
    }

    public func exceedsSynchronousThreshold(_ value: Int) -> Bool {
        return synchronousLengthThreshold.map { value >= $0 } ?? false
    }
}

extension TreeSitterClient {
    /// Prepare for a content change.
    ///
    /// This method must be called before any content changes have been applied that
    /// would affect how the `transformer`paramter will behave.
    ///
    /// - Parameter range: the range of content that will be affected by an edit
    public func willChangeContent(in range: NSRange) {
        oldEndPoint = transformer.locationToPoint(range.max)
    }

    /// Process a change in the underlying text content.
    ///
    /// This method will re-parse the sections of the content
    /// needed by tree-sitter. It may do so **asynchronously**
    /// which means you **must** guarantee that `readHandler`
    /// provides a stable, thread-safe view of the
    /// content up until `completionHandler` is called.
    ///
    /// - Parameter range: the range that was affected by the edit
    /// - Parameter delta: the change in length of the content
    /// - Parameter limit: the total length of the content
    /// - Parameter readerHandler: a function that returns the text data
    /// - Parameter completionHandler: invoked when the edit has been fully processed
    public func didChangeContent(in range: NSRange,
                                 delta: Int,
                                 limit: Int,
                                 readHandler: @escaping Parser.ReadBlock,
                                 completionHandler: @escaping () -> Void) {
        guard let oldEndPoint = oldEndPoint else {
            assertionFailure("oldEndPoint unavailable")
            return
        }

        self.oldEndPoint = nil

        guard let inputEdit = transformer.inputEdit(for: range, delta: delta, oldEndPoint: oldEndPoint) else {
            assertionFailure("unable to build InputEdit")
            return
        }

        let mutation = RangeMutation(range: range, delta: delta, limit: limit)
        let edit = ContentEdit(rangeMutation: mutation, inputEdit: inputEdit)

        processEdit(edit, readHandler: readHandler, completionHandler: completionHandler)
    }

    /// Process a string representing text content.
    ///
    /// This method is similar to `didChangeContent(in:delta:limit:readHandler:completionHandler:)`,
    /// but it makse use of the immutability of String to meet the content
    /// requirements. This makes it much easier to use. However,
    /// this approach may not be able to acheive the same level of performance.
    ///
    /// - Parameter string: the text content with the change applied
    /// - Parameter range: the range that was affected by the edit
    /// - Parameter delta: the change in length of the content
    /// - Parameter limit: the total length of the content
    /// - Parameter completionHandler: invoked when the edit has been fully processed
    public func didChangeContent(to string: String, in range: NSRange, delta: Int, limit: Int, completionHandler: @escaping () -> Void = {}) {
        let readFunction = Parser.readFunction(for: string, limit: limit)

        didChangeContent(in: range, delta: delta, limit: limit, readHandler: readFunction, completionHandler: completionHandler)
    }
}

extension TreeSitterClient {
    func processEdit(_ edit: ContentEdit, readHandler: @escaping Parser.ReadBlock, completionHandler: @escaping () -> Void) {
        let largeEdit = exceedsSynchronousThreshold(edit.size)
        let shouldEnqueue = hasQueuedEdits || largeEdit
        let doInvalidations = computeInvalidations

        self.version += 1

        guard shouldEnqueue else {
            processEditSync(edit, withInvalidations: doInvalidations, readHandler: readHandler, completionHandler: completionHandler)
            return
        }

        self.processEditAsync(edit, withInvalidations: doInvalidations, readHandler: readHandler, completionHandler: completionHandler)
    }

    private func updateState(_ newState: TreeSitterParseState, limit: Int) {
        self.parseState = newState
        self.maximumProcessedLocation = limit
    }

    private func processEditSync(_ edit: ContentEdit, withInvalidations doInvalidations: Bool, readHandler: @escaping Parser.ReadBlock, completionHandler: () -> Void) {
        let state = self.parseState

        state.applyEdit(edit.inputEdit)
        let newState = self.parser.parse(state: state, readHandler: readHandler)
        let set = doInvalidations ? self.computeInvalidatedSet(from: state, to: newState, with: edit) : IndexSet()

        updateState(newState, limit: edit.postApplyLimit)

        completionHandler()

        dispatchInvalidatedSet(set)
    }

    private func processEditAsync(_ edit: ContentEdit, withInvalidations doInvalidations: Bool, readHandler: @escaping Parser.ReadBlock, completionHandler: @escaping () -> Void) {
        outstandingEdits.append(edit)

        let state = self.parseState.copy()

        parseQueue.addAsyncOperation { opCompletion in
            state.applyEdit(edit.inputEdit)
            let newState = self.parser.parse(state: state, readHandler: readHandler)
            let set = doInvalidations ? self.computeInvalidatedSet(from: state, to: newState, with: edit) : IndexSet()

            OperationQueue.main.addOperation {
                self.updateState(newState, limit: edit.postApplyLimit)

                let completedEdit = self.outstandingEdits.removeFirst()

                assert(completedEdit.inputEdit == edit.inputEdit)

                self.dispatchInvalidatedSet(set)

                opCompletion()
                completionHandler()
            }
        }
    }

    func computeInvalidatedSet(from oldState: TreeSitterParseState, to newState: TreeSitterParseState, with edit: ContentEdit) -> IndexSet {
        let changedByteRanges = oldState.changedRanges(for: newState)
        let changedRanges = changedByteRanges.compactMap({ transformer.computeRange(from: $0) })

        // we have to ensure that any invalidated ranges don't fall outside of limit
        let clampedRanges = changedRanges.compactMap({ $0.clamped(to: edit.postApplyLimit) })

        var set = IndexSet(integersIn: edit.affectedRange)

        set.insert(ranges: clampedRanges)

        return set
    }
}

extension TreeSitterClient {
    private func transformRangeSet(_ set: IndexSet) -> IndexSet {
        let rangeMutations = outstandingEdits.map({ $0.rangeMutation })

        var transformedSet = set

        // this ensures that the set we have computed lines up with
        // the current state of the world
        for rangeMutation in rangeMutations {
            transformedSet = rangeMutation.transform(set: transformedSet)
        }

        return set
    }

    private func dispatchInvalidatedSet(_ set: IndexSet) {
        let transformedSet = transformRangeSet(set)

        if transformedSet.isEmpty {
            return
        }

        self.invalidationHandler(transformedSet)
    }
}

extension TreeSitterClient {
    public typealias ContentProvider = (NSRange) -> Result<String, Error>

    public func executeQuery(_ query: Query, in range: NSRange, contentProvider: @escaping ContentProvider, completionHandler: @escaping (Result<QueryCursor, TreeSitterClientError>) -> Void) {
        let largeRange = exceedsSynchronousThreshold(range.length)

        let shouldEnqueue = hasQueuedEdits || largeRange || range.max >= maximumProcessedLocation

        if shouldEnqueue == false {
            completionHandler(executeQuerySynchronously(query, in: range, contentProvider: contentProvider))
            return
        }

        let startedVersion = version

        let op = AsyncBlockProducerOperation<Result<QueryCursor, TreeSitterClientError>> { opCompletion in
            OperationQueue.main.addOperation {
                guard startedVersion == self.version else {
                    opCompletion(.failure(.staleContent))

                    return
                }

                assert(range.max <= self.maximumProcessedLocation)

                let result = self.executeQuerySynchronouslyWithoutCheck(query, in: range, contentProvider: contentProvider)

                opCompletion(result)
            }
        }

        op.resultCompletionBlock = completionHandler

        parseQueue.addOperation(op)
    }

    public func executeQuerySynchronously(_ query: Query, in range: NSRange, contentProvider: @escaping ContentProvider) -> Result<QueryCursor, TreeSitterClientError> {
        let shouldEnqueue = hasQueuedEdits || range.max >= maximumProcessedLocation

        if shouldEnqueue {
            return .failure(.parseStateNotUpToDate)
        }

        return executeQuerySynchronouslyWithoutCheck(query, in: range, contentProvider: contentProvider)
    }

    private func executeQuerySynchronouslyWithoutCheck(_ query: Query, in range: NSRange, contentProvider: @escaping ContentProvider) -> Result<QueryCursor, TreeSitterClientError> {
        guard let node = parseState.tree?.rootNode else {
            return .failure(.parseStateInvalid)
        }

        let textProvider: PredicateTextProvider = { (byteRange, _) -> Result<String, Error> in
            guard let range = self.transformer.computeRange(from: byteRange) else {
                return .failure(TreeSitterClientError.unableToTransformByteRange(byteRange))
            }

            return contentProvider(range)
        }

        guard let byteRange = transformer.computeByteRange(from: range) else {
            return .failure(.unableToTransformRange(range))
        }

        let cursor = query.execute(node: node, textProvider: textProvider)

        cursor.setByteRange(range: byteRange)

        return .success(cursor)
    }
}

extension TreeSitterClient {
    public struct HighlightMatch {
        public var name: String
        public var range: NSRange
    }

    private func findHighlightMatches(with cursor: QueryCursor) -> [HighlightMatch] {
        var pairs = [HighlightMatch]()

        while let match = try? cursor.nextMatch() {
            for capture in match.captures {
                guard let name = capture.name else { continue }
                let byteRange = capture.node.byteRange

                guard let range = transformer.computeRange(from: byteRange) else {
                    continue
                }

                pairs.append(HighlightMatch(name: name, range: range))
            }
        }

        return pairs
    }

    public func executeHighlightQuery(_ query: Query, in range: NSRange, contentProvider: @escaping ContentProvider, completionHandler: @escaping (Result<[HighlightMatch], TreeSitterClientError>) -> Void) {
        executeQuery(query, in: range, contentProvider: contentProvider) { result in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
            case .success(let cursor):
                let highlights = self.findHighlightMatches(with: cursor)

                completionHandler(.success(highlights))
            }
        }
    }
}
