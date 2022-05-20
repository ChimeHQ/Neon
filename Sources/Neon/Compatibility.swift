import Foundation

func preconditionOnMainQueue() {
    if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        dispatchPrecondition(condition: .onQueue(.main))
    }
}
