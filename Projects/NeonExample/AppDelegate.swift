import Cocoa
import Neon
import TreeSitterSwift

@main
class AppDelegate: NSObject, NSApplicationDelegate {
	lazy var window: NSWindow = {
		let window = NSWindow(contentViewController: ViewController())

		window.setContentSize(NSSize(width: 300.0, height: 300.0))

		return window
	}()

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		window.makeKeyAndOrderFront(self)
	}

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}
}

