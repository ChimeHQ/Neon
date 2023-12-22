import Foundation

func assumeMainActor<T>(_ body: @MainActor () throws -> T) rethrows -> T {
#if swift(>=5.9)
	if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
		return try MainActor.assumeIsolated(body)
	}
#endif

	dispatchPrecondition(condition: .onQueue(.main))
	return try withoutActuallyEscaping(body) { fn in
		try unsafeBitCast(fn, to: (() throws -> T).self)()
	}
}
