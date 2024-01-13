import Foundation

public enum RangeTarget: Hashable, Sendable {
	case set(IndexSet)
	case range(NSRange)
	case all

	public static let empty = RangeTarget.set(IndexSet())

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

	public func union(_ other: RangeTarget) -> RangeTarget {
		switch (self, other) {
		case let (.set(lhs), .set(rhs)):
			return RangeTarget.set(lhs.union(rhs))
		case (.all, _):
			return RangeTarget.all
		case (_, .all):
			return RangeTarget.all
		case let (.set(lhs), .range(rhs)):
			let set = lhs.union(IndexSet(integersIn: rhs))

			return RangeTarget.set(set)
		case let (.range(lhs), .set(rhs)):
			let set = rhs.union(IndexSet(integersIn: lhs))

			return RangeTarget.set(set)
		case let (.range(lhs), .range(rhs)):
			var set = IndexSet()

			set.insert(range: lhs)
			set.insert(range: rhs)

			return RangeTarget.set(set)
		}
	}
}
