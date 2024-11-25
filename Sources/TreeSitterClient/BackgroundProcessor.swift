import Dispatch

fileprivate struct UnsafeContainer<T>: @unchecked Sendable {
    let value: T
}

final class BackgroundProcessor<Value> {
    private let valueContainer: UnsafeContainer<Value>
    private let availabilityPredicate: () -> Bool
    private let queue = DispatchQueue(label: "com.chimehq.Neon.BackgroundAccessor")
    private var pendingCount = 0
    
    public init(value: Value, availabilityPredicate: @escaping () -> Bool ) {
        self.valueContainer = UnsafeContainer(value: value)
        self.availabilityPredicate = availabilityPredicate
    }
    
    public var hasPendingWork: Bool {
        pendingCount > 0
    }
    
    private func beginBackgroundWork() {
        precondition(pendingCount >= 0)
        pendingCount += 1
    }
    
    private func endBackgroundWork() {
        pendingCount -= 1
        precondition(pendingCount >= 0)
    }
    
    private func accessValueSynchronously() -> Value? {
        if hasPendingWork == false && availabilityPredicate() {
            return valueContainer.value
        }
        
        return nil
    }
    
    public func accessValue<T>(
        isolation: isolated (any Actor),
        preferSynchronous: Bool,
        operation: @escaping @Sendable (Value) throws -> T,
        completion: @escaping @Sendable (Result<T, Error>) -> Void
    ) {
        if preferSynchronous, let v = accessValueSynchronously() {
            precondition(hasPendingWork == false)
            
            let result = Result { try operation(v) }
            completion(result)
            
            precondition(hasPendingWork == false)
            
            return
        }
        
        
        self.beginBackgroundWork()
        
        let container = valueContainer
        
        // this is necessary to transport self from here `isolation`...
        let unsafeSelf = UnsafeContainer(value: self)
        
        queue.async {
            let result = Result { try operation(container.value) }
            
            Task {
                _ = isolation
                
                // ... to here, which is also using `isolation`. But the compiler doesn't like that.
                unsafeSelf.value.endBackgroundWork()
                
                completion(result)
            }
        }
    }
}
