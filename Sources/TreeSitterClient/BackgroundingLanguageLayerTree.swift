import Foundation

import SwiftTreeSitter
import SwiftTreeSitterLayer

enum BackgroundingLanguageLayerTreeError: Error {
	case unavailable
	case unableToSnapshot
}

final class BackgroundingLanguageLayerTree {
	public static let synchronousLengthThreshold = 2048
	public static let synchronousDocumentSize = 2048*512

	public struct Configuration {
		public let locationTransformer: Point.LocationTransformer
		public let languageProvider: LanguageLayer.LanguageProvider
		public let maximumLanguageDepth: Int

		public init(
			locationTransformer: @escaping Point.LocationTransformer,
			languageProvider: @escaping LanguageLayer.LanguageProvider = { _ in nil },
			maximumLanguageDepth: Int
		) {
			self.locationTransformer = locationTransformer
			self.languageProvider = languageProvider
			self.maximumLanguageDepth = maximumLanguageDepth
		}

		var layerConfiguration: LanguageLayer.Configuration {
			.init(maximumLanguageDepth: maximumLanguageDepth, languageProvider: languageProvider)
		}
	}

	private let queue = DispatchQueue(label: "com.chimehq.BackgroundingLanguageLayerTree")
//	private var currentVersion = 0
	private var committedVersion = 0
	private var pendingOldPoint: Point?
	private let configuration: Configuration
	private let backgroundProcessor: BackgroundProcessor<LanguageLayer>
	public var rootLanguageConfiguration: LanguageConfiguration

	public init(rootLanguageConfig: LanguageConfiguration, configuration: Configuration) throws {
		self.configuration = configuration
		self.rootLanguageConfiguration = rootLanguageConfig
		let rootLayer = try LanguageLayer(languageConfig: rootLanguageConfig, configuration: configuration.layerConfiguration)

		self.backgroundProcessor = BackgroundProcessor(value: rootLayer)
	}

	public func willChangeContent(in range: NSRange) {
		self.pendingOldPoint = configuration.locationTransformer(range.max)
	}

	public func didChangeContent(
		_ snapshot: LanguageLayer.ContentSnapshot,
		in range: NSRange,
		delta: Int,
		isolation: isolated (any Actor),
		completion: @escaping (IndexSet) -> Void
	) {
		let transformer = configuration.locationTransformer

		let smallChange = delta < Self.synchronousLengthThreshold && range.length < Self.synchronousLengthThreshold
		let smallDoc = range.max < Self.synchronousDocumentSize
		let sync = smallChange && smallDoc

		let oldEndPoint = pendingOldPoint ?? transformer(range.max) ?? .zero
		let edit = InputEdit(range: range, delta: delta, oldEndPoint: oldEndPoint, transformer: transformer)

		backgroundProcessor.accessValue(
			isolation: isolation,
			preferSynchronous: sync,
			operation: { $0.didChangeContent(snapshot.content, using: edit, resolveSublayers: false) },
			completion: { result in
				do {
					completion(try result.get())
				} catch {
					preconditionFailure("didChangeContent should not be able to fail: \(error)")
				}
			}
		)
	}

	public func languageConfigurationChanged(
		for name: String,
		content snapshot: LanguageLayer.ContentSnapshot,
		isolation: isolated (any Actor),
		completion: @escaping (Result<IndexSet, Error>) -> Void
	) {
		backgroundProcessor.accessValue(
			isolation: isolation,
			preferSynchronous: true,
			operation: { try $0.languageConfigurationChanged(for: name, content: snapshot.content) },
			completion: { result in completion(result) }
		)
	}
}

extension BackgroundingLanguageLayerTree {
	public func executeQuery(_ queryDef: Query.Definition, in set: IndexSet) throws -> LanguageTreeQueryCursor {
		return try backgroundProcessor.accessValueSynchronously() { layer in
			guard let layer else {
				throw BackgroundingLanguageLayerTreeError.unavailable
			}
			
			return try layer.executeQuery(queryDef, in: set)
		}
	}

	public func executeQuery(_ queryDef: Query.Definition, in set: IndexSet, isolation: isolated (any Actor)) async throws -> [QueryMatch] {
		let snapshot = try await backgroundProcessor.accessValue(isolation: isolation) { layer in
			guard let snapshot = layer.snapshot(in: set) else {
				throw BackgroundingLanguageLayerTreeError.unableToSnapshot
			}

			return snapshot
		}
		
		return try await Self.processSnapshot(queryDef, in: set, snapshot: snapshot)
	}

	private nonisolated static func processSnapshot(_ queryDef: Query.Definition, in set: IndexSet, snapshot: LanguageLayerTreeSnapshot) async throws -> sending [QueryMatch] {
		let cursor = try snapshot.executeQuery(queryDef, in: set)

		// this prefetches results in the background
		return cursor.map { $0 }
	}
}

extension BackgroundingLanguageLayerTree {
	public func resolveSublayers(with content: LanguageLayer.Content, in set: IndexSet) throws -> IndexSet {
		return try backgroundProcessor.accessValueSynchronously() { layer in
			guard let layer else {
				throw BackgroundingLanguageLayerTreeError.unavailable
			}
			
			return try layer.resolveSublayers(with: content, in: set)
		}
	}

	public func resolveSublayers(with snapshot: LanguageLayer.ContentSnapshot, in set: IndexSet, isolation: isolated (any Actor)) async throws -> IndexSet {
		try await backgroundProcessor.accessValue(isolation: isolation) { layer in
			try layer.resolveSublayers(with: snapshot.content, in: set)
		}
	}
}
