import AppKit
import SwiftUI

@main
struct MuescaMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // sin icono en el Dock ni barra de menús
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchController()
        controller.show()
        self.controller = controller

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.controller?.rebuild()
            self?.controller?.brightness.external.reconnect()
        }
    }
}
