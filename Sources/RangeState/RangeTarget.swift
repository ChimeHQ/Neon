import Foundation

import Rearrange

public enum RangeTarget: Hashable, Sendable {
	case set(IndexSet)
	case range(NSRange)
	case all

	public static let empty = RangeTarget.set(IndexSet())

	public init(_ set: IndexSet) {
		self = .set(set)
	}

	public init(_ range: NSRange) {
		self = .range(range)
	}

	public init(_ ranges: [NSRange]) {
		self = .set(IndexSet(ranges: ranges))
	}

	public func indexSet(with length: Int) -> IndexSet {
		let set: IndexSet

		switch self {
		case .set(let indexSet):
			set = indexSet
		case .range(let range):
			set = IndexSet(integersIn: range)
		case .all:
			set = IndexSet(integersIn: 0..<length)
		}

		return set
	}
}

extension RangeTarget {
	public func union(_ other: RangeTarget) -> RangeTarget {
		switch (self, other) {
		case (.set(var set), .set(let rhs)):
			set.formUnion(rhs)
			return RangeTarget(set)
		case (.all, _):
			return RangeTarget.all
		case (_, .all):
			return RangeTarget.all
		case (.set(var set), .range(let range)):
			set.insert(range: range)

			return RangeTarget(set)
		case let (.range(lhs), .set(rhs)):
			let set = rhs.union(IndexSet(integersIn: lhs))

			return RangeTarget(set)
		case let (.range(lhs), .range(rhs)):
			return RangeTarget([lhs, rhs])
		}
	}

	public func apply(mutations: [RangeMutation]) -> RangeTarget {
		switch self {
		case .all:
			return .all
		case var .range(range):
			for mutation in mutations {
				guard let newRange = range.apply(mutation) else {
					return .empty
				}

				range = newRange
			}

			return .range(range)
		case var .set(set):
			set.applying(mutations)

			return .set(set)
		}
	}
}

extension RangeTarget: CustomDebugStringConvertible {
	public var debugDescription: String {
		switch self {
		case .all:
			"all"
		case let .range(range):
			range.debugDescription
		case let .set(set):
			set.nsRangeView.debugDescription
		}
	}
}

