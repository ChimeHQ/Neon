import Foundation

public enum TextTarget {
    case set(IndexSet)
    case range(NSRange)
    case all

    public func indexSet(with fullSet: IndexSet) -> IndexSet {
        let set: IndexSet

        switch self {
        case .set(let indexSet):
            set = indexSet
        case .range(let range):
            set = IndexSet(integersIn: range)
        case .all:
            set = fullSet
        }

        return set
    }
}