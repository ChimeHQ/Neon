import Foundation
import os.log

import RangeState
import Rearrange
import SwiftTreeSitter
import SwiftTreeSitterLayer

enum TreeSitterClientError: Error {
	case languageUnavailable(String)
}

@MainActor
public final class TreeSitterClient {
	public typealias TextProvider = SwiftTreeSitter.Predicate.TextProvider
	public typealias ContentProvider = (Int) -> LanguageLayer.Content
	private typealias SublayerValidator = RangeValidator<UnversionableContent>

	private static let deltaRange = 128..<Int.max
	private let logger = OSLog(subsystem: "com.chimehq.Neon", category: "TreeSitterClient")

	public struct Configuration {
		public let languageProvider: LanguageLayer.LanguageProvider
		public let contentProvider: ContentProvider
		public let lengthProvider: RangeProcessor.LengthProvider
		public let invalidationHandler: (IndexSet) -> Void
		public let locationTransformer: (Int) -> Point?

		/// Create the client configuration.
		///
		/// The `invalidationHandler` function always returns values that represent the current state of the content, even if the system is working in the background.
		///
		/// - Parameter languageProvider: called when nested language configuration is needed.
		/// - Parameter invalidationHandler: invoked when parts of the text content have changed.
		///
		public init(
			languageProvider: @escaping LanguageLayer.LanguageProvider = { _ in nil },
			contentProvider: @escaping (Int) -> LanguageLayer.Content,
			lengthProvider: @escaping RangeProcessor.LengthProvider,
			invalidationHandler: @escaping (IndexSet) -> Void,
			locationTransformer: @escaping (Int) -> Point?
		) {
			self.languageProvider = languageProvider
			self.contentProvider = contentProvider
			self.lengthProvider = lengthProvider
			self.invalidationHandler = invalidationHandler
			self.locationTransformer = locationTransformer
		}
	}

	private var versionedContent: UnversionableContent
	private let configuration: Configuration
	private lazy var rangeProcessor = RangeProcessor(
		configuration: .init(
			deltaRange: Self.deltaRange,
			lengthProvider: configuration.lengthProvider,
			changeHandler: { [unowned self] in self.didChange($0) }
		)
	)
	private lazy var sublayerValidator = SublayerValidator(
		configuration: .init(
			versionedContent: versionedContent,
			validationProvider: validatorProvider
		)
	)

	private let layerTree: BackgroundingLanguageLayerTree
	private let queue = DispatchQueue(label: "com.chimehq.HybridTreeSitterClient")

	public init(rootLanguageConfig: LanguageConfiguration, configuration: Configuration) throws {
		self.configuration = configuration
		self.versionedContent = UnversionableContent(lengthProvider: configuration.lengthProvider)
		self.layerTree = try BackgroundingLanguageLayerTree(
			rootLanguageConfig: rootLanguageConfig,
			configuration: .init(
				locationTransformer: configuration.locationTransformer,
				languageProvider: configuration.languageProvider
			)
		)
	}

	/// Prepare for a content change.
	///
	/// This method must be called before any content changes have been applied that would affect how the `locationTransformer` configuration will behave.
	///
	/// - Parameter range: the range of content that will be affected by an edit
	public func willChangeContent(in range: NSRange) {
		layerTree.willChangeContent(in: range)
	}

	/// Process a change in the underlying text content.
	///
	/// This method will re-parse the sections of the content needed by tree-sitter. It may do so **asynchronously**.
	///
	/// - Parameter range: the range that was affected by the edit
	/// - Parameter delta: the change in length of the content
	public func didChangeContent(in range: NSRange, delta: Int) {
		rangeProcessor.didChangeContent(in: range, delta: delta)
		sublayerValidator.contentChanged(in: range, delta: delta)
		versionedContent.contentChanged()
	}

	/// Inform the client that calls to `languageConfiguration` may change.
	public func languageConfigurationChanged(for name: String) {
		let content = maximumProcessedContent

		layerTree.languageConfigurationChanged(for: name, content: content) { result in
			do {
				let invalidated = try result.get()

				self.handleInvalidation(invalidated, sublayers: true)
			} catch {
				fatalError("failed to process language configuration change, how do we handle this? \(error)")
			}
		}
	}

	private var maximumProcessedContent: LanguageLayer.Content {
		configuration.contentProvider(rangeProcessor.maximumProcessedLocation)
	}
}

extension TreeSitterClient {
	private var hasPendingChanges: Bool {
		rangeProcessor.hasPendingChanges
	}

	private func didChange(_ mutation: RangeMutation) {
		let limit = mutation.postApplyLimit

		let content = configuration.contentProvider(limit)

		layerTree.didChangeContent(content, in: mutation.range, delta: mutation.delta, completion: { invalidated in
			self.completeChange(mutation, invalidating: invalidated)
		})
	}

	private func completeChange(_ mutation: RangeMutation, invalidating invalidated: IndexSet) {
		rangeProcessor.completeContentChanged(mutation)

		handleInvalidation(invalidated, sublayers: false)
	}

	private func handleInvalidation(_ set: IndexSet, sublayers: Bool) {
		let transformedSet = set.apply(rangeProcessor.pendingMutations)

		configuration.invalidationHandler(transformedSet)

		if sublayers {
			sublayerValidator.invalidate(.set(transformedSet))
		}
	}

	private func languageConfig(for name: String) -> LanguageConfiguration? {
		configuration.languageProvider(name)
	}
}

extension TreeSitterClient {
	private func resolveSublayers(in range: NSRange) -> Bool {
		guard self.canAttemptSynchronousAccess(in: .range(range)) else {
			return false
		}

		let set = IndexSet(integersIn: range)
		let content = self.maximumProcessedContent

		do {
			let invalidatedSet = try self.layerTree.resolveSublayers(with: content, in: set)

			self.handleInvalidation(invalidatedSet, sublayers: false)
		} catch {
			os_log(.fault, log: self.logger, "Failed resolve sublayers", String(describing: error))
		}

		return true
	}

	private func resolveSublayers(in range: NSRange) async {
		let set = IndexSet(integersIn: range)
		let content = self.maximumProcessedContent

		do {
			let invalidatedSet = try await self.layerTree.resolveSublayers(with: content, in: set)

			self.handleInvalidation(invalidatedSet, sublayers: false)
		} catch {
			os_log(.fault, log: self.logger, "Failed resolve sublayers", String(describing: error))
		}
	}

	private var validatorProvider: SublayerValidator.ValidationProvider {
		.init(
			rangeProcessor: rangeProcessor,
			inputTransformer: { ($0.value.max, .optional) },
			syncValue: { versioned in
				guard versioned.version == self.versionedContent.currentVersion else {
					return .stale
				}

				guard self.resolveSublayers(in: versioned.value) else {
					return nil
				}

				return .success(versioned.value)

			},
			asyncValue: { versioned in
				guard versioned.version == self.versionedContent.currentVersion else {
					return .stale
				}

				await self.resolveSublayers(in: versioned.value)

				// have to check on both sides of the await
				guard versioned.version == self.versionedContent.currentVersion else {
					return .stale
				}

				return .success(versioned.value)
			}
		)
	}
}

extension TreeSitterClient {
	@MainActor
	public struct ClientQueryParams {
		public let indexSet: IndexSet
		public let textProvider: TextProvider
		public let mode: RangeFillMode

		public init(indexSet: IndexSet, textProvider: @escaping TextProvider, mode: RangeFillMode = .required) {
			self.indexSet = indexSet
			self.textProvider = textProvider
			self.mode = mode
		}

		public init(range: NSRange, textProvider: @escaping TextProvider, mode: RangeFillMode = .required) {
			self.indexSet = IndexSet(integersIn: range)
			self.textProvider = textProvider
			self.mode = mode
		}

		public var maxLocation: Int {
			indexSet.max() ?? 0
		}
	}

	@MainActor
	public struct ClientQuery {
		public let query: Query.Definition
		public let params: ClientQueryParams

		public init(query: Query.Definition, indexSet: IndexSet, textProvider: @escaping TextProvider, mode: RangeFillMode = .required) {
			self.query = query
			self.params = ClientQueryParams(indexSet: indexSet, textProvider: textProvider, mode: mode)
		}

		public init(query: Query.Definition, range: NSRange, textProvider: @escaping TextProvider, mode: RangeFillMode = .required) {
			self.query = query
			self.params = ClientQueryParams(range: range, textProvider: textProvider, mode: mode)
		}
	}

	public func canAttemptSynchronousAccess(in target: RangeTarget) -> Bool {
		return hasPendingChanges == false
	}

	private func validateSublayers(in set: IndexSet) {
		sublayerValidator.validate(.set(set))
	}

	private func executeQuery(_ clientQuery: ClientQuery) async throws -> some Sequence<QueryMatch> {
		rangeProcessor.processLocation(clientQuery.params.maxLocation, mode: clientQuery.params.mode)

		await rangeProcessor.processingCompleted()

		validateSublayers(in: clientQuery.params.indexSet)

		let matches = try await layerTree.executeQuery(clientQuery.query, in: clientQuery.params.indexSet)

		return matches.resolve(with: .init(textProvider: clientQuery.params.textProvider))
	}

	public var highlightsProvider: HybridThrowingValueProvider<ClientQueryParams, [NamedRange]> {
		.init(
			rangeProcessor: rangeProcessor,
			inputTransformer: { ($0.maxLocation, $0.mode) },
			syncValue: { input in
				let set = input.indexSet

				guard self.canAttemptSynchronousAccess(in: .set(set)) else { return [] }

				self.validateSublayers(in: set)

				return try self.layerTree.executeQuery(.highlights, in: set).highlights()
			},
			asyncValue: { input in
				let query = ClientQuery(query: .highlights, indexSet: input.indexSet, textProvider: input.textProvider, mode: input.mode)

				return try await self.executeQuery(query).highlights()
			})
	}
}

extension TreeSitterClient {
	/// Execute a standard highlights.scm query.
	public func highlights(in set: IndexSet, provider: @escaping TextProvider, mode: RangeFillMode = .required) async throws -> [NamedRange] {
		try await highlightsProvider.async(.init(indexSet: set, textProvider: provider, mode: mode))
	}

	/// Execute a standard highlights.scm query.
	public func highlights(in range: NSRange, provider: @escaping TextProvider, mode: RangeFillMode = .required) throws -> [NamedRange]? {
		try highlightsProvider.sync(.init(range: range, textProvider: provider, mode: mode))
	}

	/// Execute a standard highlights.scm query.
	public func highlights(in range: NSRange, provider: @escaping TextProvider, mode: RangeFillMode = .required) async throws -> [NamedRange] {
		try await highlightsProvider.async(.init(range: range, textProvider: provider, mode: mode))
	}
}
