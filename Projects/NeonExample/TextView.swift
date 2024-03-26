import SwiftUI
import NSUI

@MainActor
struct TextView: NSUIViewControllerRepresentable {
	typealias NSUIViewControllerType = TextViewController
	func makeNSUIViewController(context: Context) -> TextViewController {
		TextViewController()
	}

	func updateNSUIViewController(_ viewController: TextViewController, context: Context) {
	}
}
