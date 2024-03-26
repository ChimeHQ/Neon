import Foundation

import ConcurrencyCompatibility
import SwiftTreeSitter
import SwiftTreeSitterLayer

enum BackgroundingLanguageLayerTreeError: Error {
	case unavailable
	case unableToSnapshot
}

@MainActor
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

	private let queue = DispatchQueue(label: "com.chimehq.QueuedLanguageLayerTree")
	private var currentVersion = 0
	private var committedVersion = 0
	private var pendingOldPoint: Point?
	private let rootLayer: LanguageLayer
	private let configuration: Configuration

	public init(rootLanguageConfig: LanguageConfiguration, configuration: Configuration) throws {
		self.configuration = configuration
		self.rootLayer = try LanguageLayer(languageConfig: rootLanguageConfig, configuration: configuration.layerConfiguration)
	}

	private func accessTreeSynchronously(version: Int) -> LanguageLayer? {
		guard version == committedVersion else { return nil }

		return rootLayer
	}

	private func accessTree<T>(
		version: Int,
		preferSynchronous: Bool,
		operation: @escaping (LanguageLayer) throws -> T,
		completion: @escaping @MainActor (Result<T, Error>) -> Void
	) {
		if preferSynchronous, let tree = accessTreeSynchronously(version: version) {
			let result = Result(catching: { try operation(tree) })
			completion(result)
			return
		}

		// this must be unsafe because LanguageLayerTree is not Sendable. However access is gated through the main actor/queue.
		queue.backport.asyncUnsafe { [rootLayer] in
			let result = Result(catching: { try operation(rootLayer) })

			DispatchQueue.main.async {
				completion(result)
			}
		}
	}

	public func willChangeContent(in range: NSRange) {
		self.pendingOldPoint = configuration.locationTransformer(range.max)
	}

	public func didChangeContent(_ content: LanguageLayer.Content, in range: NSRange, delta: Int, completion: @escaping @MainActor (IndexSet) -> Void) {
		let transformer = configuration.locationTransformer

		let upToDate = currentVersion == committedVersion
		let smallChange = delta < Self.synchronousLengthThreshold && range.length < Self.synchronousLengthThreshold
		let smallDoc = range.max < Self.synchronousDocumentSize
		let sync = upToDate && smallChange && smallDoc

		let version = currentVersion
		self.currentVersion += 1

		let oldEndPoint = pendingOldPoint ?? transformer(range.max) ?? .zero
		let edit = InputEdit(range: range, delta: delta, oldEndPoint: oldEndPoint, transformer: transformer)

		accessTree(version: version, preferSynchronous: sync) { tree in
			tree.didChangeContent(content, using: edit, resolveSublayers: false)
		} completion: { result in
			self.committedVersion += 1

			do {
				completion(try result.get())
			} catch {
				preconditionFailure("didChangeContent should not be able to fail: \(error)")
			}
		}
	}

	public func languageConfigurationChanged(for name: String, content: LanguageLayer.Content, completion: @escaping @MainActor (Result<IndexSet, Error>) -> Void) {
		accessTree(version: currentVersion, preferSynchronous: true) { tree in
			try tree.languageConfigurationChanged(for: name, content: content)
		} completion: {
			completion($0)
		}
	}
}

extension BackgroundingLanguageLayerTree {
	public func executeQuery(_ queryDef: Query.Definition, in set: IndexSet) throws -> LanguageTreeQueryCursor {
		guard let tree = accessTreeSynchronously(version: currentVersion) else {
			throw BackgroundingLanguageLayerTreeError.unavailable
		}

		return try tree.executeQuery(queryDef, in: set)
	}

	public func executeQuery(_ queryDef: Query.Definition, in set: IndexSet) async throws -> [QueryMatch] {
		try await withCheckedThrowingContinuation { continuation in
			accessTree(version: currentVersion, preferSynchronous: false) { tree in
				guard let snapshot = tree.snapshot(in: set) else {
					throw BackgroundingLanguageLayerTreeError.unableToSnapshot
				}

				return snapshot
			} completion: { result in
				DispatchQueue.global().backport.asyncUnsafe {
					let cursorResult = result.flatMap { snapshot in
						Result(catching: {
							let cursor = try snapshot.executeQuery(queryDef, in: set)

							// this prefetches results in the background
							return cursor.map { $0 }
						})
					}

					continuation.resume(with: cursorResult)
				}
			}
		}
	}
}

extension BackgroundingLanguageLayerTree {
	public func resolveSublayers(with content: LanguageLayer.Content, in set: IndexSet) throws -> IndexSet {
		guard let tree = accessTreeSynchronously(version: currentVersion) else {
			throw BackgroundingLanguageLayerTreeError.unavailable
		}

		return try tree.resolveSublayers(with: content, in: set)
	}

	public func resolveSublayers(with content: LanguageLayer.Content, in set: IndexSet) async throws -> IndexSet {
		try await withCheckedThrowingContinuation { continuation in
			accessTree(version: currentVersion, preferSynchronous: false) { tree in
				try tree.resolveSublayers(with: content, in: set)
			} completion: { result in
				continuation.resume(with: result)
			}
		}
	}
}
