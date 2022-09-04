import Foundation
import SwiftTreeSitter
import Rearrange

public enum TreeSitterClientError: Error {
    case staleState
    case stateInvalid
    case staleContent
    case queryFailed(Error)
    case asyncronousExecutionRequired
}

public final class TreeSitterClient {
    public enum ExecutionMode: Hashable {
        case synchronous
        case synchronousPreferred
        case failIfAsynchronous
        case asynchronous(prefetch: Bool = true)
    }

    struct ContentEdit {
        var rangeMutation: RangeMutation
        var inputEdit: InputEdit
        var limit: Int

        var size: Int {
            return max(abs(rangeMutation.delta), rangeMutation.range.length)
        }

        var affectedRange: NSRange {
            let range = rangeMutation.range

            // we want to expand our affected range just slightly, so that
            // changes to immediately-adjacent tokens are included in the range checks
            // for the cursor.
            let start = max(range.location - 1, 0)
            let end = min(max(range.max, range.max + rangeMutation.delta) + 1, limit)

            return NSRange(start..<end)
        }
    }

    private var oldEndPoint: Point?
    private let parser: Parser
    private var parseState: TreeSitterParseState
    private var outstandingEdits: [ContentEdit]
    private var version: Int
    private let queue: DispatchQueue
    private let semaphore: DispatchSemaphore
    private let synchronousLengthThreshold: Int

    // This was roughly determined to be the limit in characters
    // before it's likely that tree-sitter edit processing
    // and tree-diffing will start to become noticibly laggy
    private let synchronousContentLengthThreshold: Int = 1_000_000

    public let locationTransformer: Point.LocationTransformer?
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

    public init(language: Language, transformer: Point.LocationTransformer? = nil, synchronousLengthThreshold: Int = 1024) throws {
        self.parser = Parser()
        self.parseState = TreeSitterParseState(tree: nil)
        self.outstandingEdits = []
        self.computeInvalidations = true
        self.version = 0
        self.queue = DispatchQueue(label: "com.chimehq.Neon.TreeSitterClient")
        self.semaphore = DispatchSemaphore(value: 1)

        try parser.setLanguage(language)

        self.invalidationHandler = { _ in }
        self.locationTransformer = transformer
        self.synchronousLengthThreshold = synchronousLengthThreshold
    }

    private var hasQueuedWork: Bool {
        return outstandingEdits.count > 0
    }
}

extension TreeSitterClient {
    /// Prepare for a content change.
    ///
    /// This method must be called before any content changes have been applied that
    /// would affect how the `transformer`parameter will behave.
    ///
    /// - Parameter range: the range of content that will be affected by an edit
    public func willChangeContent(in range: NSRange) {
        oldEndPoint = locationTransformer?(range.max)
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
    /// - Parameter limit: the current length of the content
    /// - Parameter readerHandler: a function that returns the text data
    /// - Parameter completionHandler: invoked when the edit has been fully processed
    public func didChangeContent(in range: NSRange,
                                 delta: Int,
                                 limit: Int,
                                 readHandler: @escaping Parser.ReadBlock,
                                 completionHandler: @escaping () -> Void) {
        if locationTransformer != nil && oldEndPoint == nil {
            assertionFailure("oldEndPoint unavailable")
            return
        }
        let oldEndPoint = self.oldEndPoint ?? .zero
        self.oldEndPoint = nil

        guard let inputEdit = InputEdit(range: range, delta: delta, oldEndPoint: oldEndPoint, transformer: locationTransformer) else {
            assertionFailure("unable to build InputEdit")
            return
        }

        // RangeMutation has a "limit" concept, used for bounds checking. However,
        // they are treated as pre-application of the mutation. Here, the content
        // has already changed. That's why it's optional!
        //
        // So, why use RangeMutation at all? Because we want to make use of its
        // tranformation capabilities for invalidations.
        let mutation = RangeMutation(range: range, delta: delta)
        let edit = ContentEdit(rangeMutation: mutation, inputEdit: inputEdit, limit: limit)

        processEdit(edit, readHandler: readHandler, completionHandler: completionHandler)
    }

    /// Process a string representing text content.
    ///
    /// This method is similar to `didChangeContent(in:delta:limit:readHandler:completionHandler:)`,
    /// but it makes use of the immutability of String to meet the content
    /// requirements. This makes it much easier to use. However,
    /// this approach may not be able to acheive the same level of performance.
    ///
    /// - Parameter string: the text content with the change applied
    /// - Parameter range: the range that was affected by the edit
    /// - Parameter delta: the change in length of the content
    /// - Parameter limit: the current length of the content
    /// - Parameter completionHandler: invoked when the edit has been fully processed
    public func didChangeContent(to string: String, in range: NSRange, delta: Int, limit: Int, completionHandler: @escaping () -> Void = {}) {
        let readFunction = Parser.readFunction(for: string, limit: limit)

        didChangeContent(in: range, delta: delta, limit: limit, readHandler: readFunction, completionHandler: completionHandler)
    }
}

extension TreeSitterClient {
    func processEdit(_ edit: ContentEdit, readHandler: @escaping Parser.ReadBlock, completionHandler: @escaping () -> Void) {
        preconditionOnMainQueue()

        let largeEdit = edit.size > synchronousLengthThreshold
        let largeDocument = edit.limit > synchronousContentLengthThreshold
        let runAsync = hasQueuedWork || largeEdit || largeDocument
        let doInvalidations = computeInvalidations

        if runAsync == false {
            processEditSync(edit, withInvalidations: doInvalidations, readHandler: readHandler, completionHandler: completionHandler)
            return
        }

        processEditAsync(edit, withInvalidations: doInvalidations, readHandler: readHandler, completionHandler: completionHandler)
    }

    private func applyEdit(_ edit: ContentEdit, readHandler: @escaping Parser.ReadBlock) -> (TreeSitterParseState, TreeSitterParseState) {
        self.semaphore.wait()
        let state = self.parseState

        state.applyEdit(edit.inputEdit)
        self.parseState = self.parser.parse(state: state, readHandler: readHandler)

        let oldState = state.copy()
        let newState = parseState.copy()

        self.semaphore.signal()

        return (oldState, newState)
    }

    private func processEditSync(_ edit: ContentEdit, withInvalidations doInvalidations: Bool, readHandler: @escaping Parser.ReadBlock, completionHandler: () -> Void) {
        let (oldState, newState) = applyEdit(edit, readHandler: readHandler)

        let set = doInvalidations ? self.computeInvalidatedSet(from: oldState, to: newState, with: edit) : IndexSet()

        completionHandler()

        dispatchInvalidatedSet(set)
    }

    private func processEditAsync(_ edit: ContentEdit, withInvalidations doInvalidations: Bool, readHandler: @escaping Parser.ReadBlock, completionHandler: @escaping () -> Void) {
        outstandingEdits.append(edit)

        queue.async {
            let (oldState, newState) = self.applyEdit(edit, readHandler: readHandler)

            DispatchQueue.global().async {
                // we can safely compute the invalidations on another queue
                let set = doInvalidations ? self.computeInvalidatedSet(from: oldState, to: newState, with: edit) : IndexSet()

                OperationQueue.main.addOperation {
                    let completedEdit = self.outstandingEdits.removeFirst()

                    assert(completedEdit.inputEdit == edit.inputEdit)

                    self.dispatchInvalidatedSet(set)

                    completionHandler()
                }
            }
        }
    }

    func computeInvalidatedSet(from oldState: TreeSitterParseState, to newState: TreeSitterParseState, with edit: ContentEdit) -> IndexSet {
        let changedRanges = oldState.changedByteRanges(for: newState).map({ $0.range })

        // we have to ensure that any invalidated ranges don't fall outside of limit
        let clampedRanges = changedRanges.compactMap({ $0.clamped(to: edit.limit) })

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
		preconditionOnMainQueue()
		
        let transformedSet = transformRangeSet(set)

        if transformedSet.isEmpty {
            return
        }

        self.invalidationHandler(transformedSet)
    }
}

extension TreeSitterClient {
    public typealias QueryCursorResult = Result<QueryCursor, TreeSitterClientError>
    public typealias ResolvingQueryCursorResult = Result<ResolvingQueryCursor, TreeSitterClientError>

    /// Determine if it is likely that a synchronous query will execute quickly
    public func canAttemptSynchronousQuery(in range: NSRange) -> Bool {
        let largeRange = range.length > synchronousLengthThreshold
        let largeLocation = range.max > synchronousContentLengthThreshold

        return (hasQueuedWork || largeRange || largeLocation) == false
    }

    /// Executes a query and returns a ResolvingQueryCursor
    ///
    /// This method runs a query on the current state of the content. It guarantees
    /// that a successful result corresponds to that state. It must be invoked from
    /// the main thread and will always call `completionHandler` on the main thread as well.
    ///
    /// - Parameter query: the query to execute
    /// - Parameter range: constrain the query to this range
    /// - Parameter executionMode: determine if a background query should be used
    /// - Parameter completionHandler: returns the result
    public func executeResolvingQuery(_ query: Query,
                                      in range: NSRange,
                                      executionMode: ExecutionMode = .asynchronous(prefetch: true),
                                      completionHandler: @escaping (ResolvingQueryCursorResult) -> Void) {
        preconditionOnMainQueue()

        let prefetchMatches: Bool

        switch executionMode {
        case .synchronous:
            let result = executeResolvingQuerySynchronously(query, in: range)
            completionHandler(result)
            return
        case .failIfAsynchronous:
            if canAttemptSynchronousQuery(in: range) == false {
                completionHandler(.failure(.asyncronousExecutionRequired))
            } else {
                let result = executeResolvingQuerySynchronously(query, in: range)
                completionHandler(result)
            }

            return
        case .synchronousPreferred:
            if canAttemptSynchronousQuery(in: range) {
                let result = executeResolvingQuerySynchronously(query, in: range)
                completionHandler(result)
                return
            }

            prefetchMatches = true
        case .asynchronous(let prefetch):
            prefetchMatches = prefetch
        }

        // We only want to produce results that match the *current* state
        // of the content...
        let startedVersion = version

        queue.async {
            // .. so at the state could be mutated at at any point. But,
            // let's be optimistic and only check once at the end.

            self.semaphore.wait()
            let state = self.parseState.copy()
            self.semaphore.signal()

            DispatchQueue.global().async {
                let result = self.executeResolvingQuerySynchronouslyWithoutCheck(query,
                                                                                 in: range,
                                                                                 with: state)

                if case .success(let cursor) = result, prefetchMatches {
                    cursor.prefetchMatches()
                }

                OperationQueue.main.addOperation {
                    guard startedVersion == self.version else {
                        completionHandler(.failure(.staleContent))

                        return
                    }

                    completionHandler(result)
                }
            }
        }
    }

    /// Executes a query and returns a ResolvingQueryCursor
    ///
    /// This is the async version of executeResolvingQuery(:in:preferSynchronous:prefetchMatches:completionHandler:)
    @available(macOS 10.15, iOS 13.0, watchOS 6.0.0, tvOS 13.0.0, *)
    @MainActor
    public func resolvingQueryCursor(with query: Query,
                                     in range: NSRange,
                                     executionMode: ExecutionMode = .asynchronous(prefetch: true)) async throws -> ResolvingQueryCursor {
        try await withCheckedThrowingContinuation { continuation in
            self.executeResolvingQuery(query, in: range, executionMode: executionMode) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Fetches the current stable version of Tree
    ///
    /// This function always fetches tree that represents the current state of the content, even if the
    /// system is working in the background.
    public func currentTree(completionHandler: @escaping (Result<Tree, TreeSitterClientError>) -> Void) {
        let startedVersion = version
        queue.async {
            self.semaphore.wait()
            let state = self.parseState.copy()
            self.semaphore.signal()

            OperationQueue.main.addOperation {
                guard startedVersion == self.version else {
                    completionHandler(.failure(.staleContent))
                    return
                }
                if let tree = state.tree {
                    completionHandler(.success(tree))
                } else {
                    completionHandler(.failure(.stateInvalid))
                }
            }
        }
    }
}

extension TreeSitterClient {
    public func executeResolvingQuerySynchronously(_ query: Query, in range: NSRange) -> ResolvingQueryCursorResult {
        preconditionOnMainQueue()

        if hasQueuedWork {
            return .failure(.staleState)
        }

        return executeResolvingQuerySynchronouslyWithoutCheck(query, in: range, with: parseState)
    }

    private func executeResolvingQuerySynchronouslyWithoutCheck(_ query: Query, in range: NSRange, with state: TreeSitterParseState) -> ResolvingQueryCursorResult {
        return executeQuerySynchronouslyWithoutCheck(query, in: range, with: state)
            .map({ ResolvingQueryCursor(cursor: $0) })
    }
}

extension TreeSitterClient {
    public func executeQuerySynchronously(_ query: Query, in range: NSRange) -> QueryCursorResult {
        preconditionOnMainQueue()

        if hasQueuedWork {
            return .failure(.staleState)
        }

        return executeQuerySynchronouslyWithoutCheck(query, in: range, with: parseState)
    }

    private func executeQuerySynchronouslyWithoutCheck(_ query: Query, in range: NSRange, with state: TreeSitterParseState) -> QueryCursorResult {
        guard let node = state.tree?.rootNode else {
            return .failure(.stateInvalid)
        }

        // critical to keep a reference to the tree, so it survives as long as the query
        let cursor = query.execute(node: node, in: state.tree)

        cursor.setRange(range)

        return .success(cursor)
    }
}

