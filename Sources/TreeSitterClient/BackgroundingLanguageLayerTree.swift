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
	public struct Configuration {
		public let locationTransformer: Point.LocationTransformer
		public let languageProvider: LanguageLayer.LanguageProvider

		public init(
			locationTransformer: @escaping Point.LocationTransformer,
			languageProvider: @escaping LanguageLayer.LanguageProvider = { _ in nil }
		) {
			self.locationTransformer = locationTransformer
			self.languageProvider = languageProvider
		}

		var layerConfiguration: LanguageLayer.Configuration {
			.init(languageProvider: languageProvider)
		}
	}

	private let queue = DispatchQueue(label: "com.chimehq.QueuedLanguageLayerTree")
	private var version = 0
	private var commitedVersion = 0
	private var pendingOldPoint: Point?
	private let rootLayer: LanguageLayer
	private let configuration: Configuration

	public init(rootLanguageConfig: LanguageConfiguration, configuration: Configuration) throws {
		self.configuration = configuration
		self.rootLayer = try LanguageLayer(languageConfig: rootLanguageConfig, configuration: configuration.layerConfiguration)
	}

	private var pendingWork: Bool {
		version != commitedVersion
	}

	private func accessTreeSynchronously() -> LanguageLayer? {
		guard pendingWork == false else { return nil }

		return rootLayer
	}

	private func accessTree<T>(
		operation: @escaping (LanguageLayer) throws -> T,
		completion: @escaping @MainActor (Result<T, Error>) -> Void
	) {
		if let tree = accessTreeSynchronously() {
			let result = Result(catching: { try operation(tree) })
			completion(result)
			return
		}

		// this must be unsafe because LanguageLayerTree is not Sendable. However access is gated through the main actor/queue.
		queue.asyncUnsafe { [rootLayer] in
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

		self.version += 1

		let oldEndPoint = pendingOldPoint ?? transformer(range.max) ?? .zero
		let edit = InputEdit(range: range, delta: delta, oldEndPoint: oldEndPoint, transformer: transformer)

		accessTree { tree in
			tree.didChangeContent(content, using: edit, resolveSublayers: false)
		} completion: { result in
			self.commitedVersion += 1

			do {
				completion(try result.get())
			} catch {
				preconditionFailure("didChangeContent should not be able to fail: \(error)")
			}
		}
	}

	public func languageConfigurationChanged(for name: String, content: LanguageLayer.Content, completion: @escaping @MainActor (Result<IndexSet, Error>) -> Void) {
		accessTree { tree in
			try tree.languageConfigurationChanged(for: name, content: content)
		} completion: {
			completion($0)
		}
	}
}

extension BackgroundingLanguageLayerTree {
	public func executeQuery(_ queryDef: Query.Definition, in set: IndexSet) throws -> LanguageTreeQueryCursor {
		guard let tree = accessTreeSynchronously() else {
			throw BackgroundingLanguageLayerTreeError.unavailable
		}

		return try tree.executeQuery(queryDef, in: set)
	}

	public func executeQuery(_ queryDef: Query.Definition, in set: IndexSet) async throws -> [QueryMatch] {
		try await withCheckedThrowingContinuation { continuation in
			accessTree { tree in
				guard let snapshot = tree.snapshot(in: set) else {
					throw BackgroundingLanguageLayerTreeError.unableToSnapshot
				}

				return snapshot
			} completion: { result in
				DispatchQueue.global().asyncUnsafe {
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
		guard let tree = accessTreeSynchronously() else {
			throw BackgroundingLanguageLayerTreeError.unavailable
		}

		return try tree.resolveSublayers(with: content, in: set)
	}

	public func resolveSublayers(with content: LanguageLayer.Content, in set: IndexSet) async throws -> IndexSet {
		try await withCheckedThrowingContinuation { continuation in
			accessTree { tree in
				try tree.resolveSublayers(with: content, in: set)
			} completion: { result in
				continuation.resume(with: result)
			}
		}
	}
}
