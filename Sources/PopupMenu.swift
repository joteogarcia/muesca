import AppKit
import SwiftUI

/// Menú nativo de macOS lanzado desde la isla (los menús contextuales de SwiftUI
/// no aparecen en una ventana que no se activa).
struct PopupItem {
    let title: String
    var symbol: String? = nil
    var isSeparator = false
    var action: () -> Void = {}

    static var separator: PopupItem { PopupItem(title: "", isSeparator: true) }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ item: PopupItem) {
        handler = item.action
        super.init(title: item.title, action: #selector(fire), keyEquivalent: "")
        target = self
        if let s = item.symbol { image = NSImage(systemSymbolName: s, accessibilityDescription: nil) }
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

enum PopupMenu {
    /// Abre el menú en la posición del ratón. Lo gestiona el controlador
    /// para que la isla no se cierre mientras el menú está abierto.
    static func show(_ items: [PopupItem]) {
        NotificationCenter.default.post(name: .showPopupMenu, object: items)
    }

    static func build(_ items: [PopupItem]) -> NSMenu {
        let menu = NSMenu()
        for i in items { menu.addItem(i.isSeparator ? .separator() : ClosureMenuItem(i)) }
        return menu
    }
}

extension Notification.Name {
    static let showPopupMenu = Notification.Name("Muesca.showPopupMenu")
}

/// Captura solo el clic derecho; el resto de clics pasan a lo que hay encima.
final class RightClickView: NSView {
    var onRightClick: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? {
        let t = NSApp.currentEvent?.type
        return (t == .rightMouseDown || t == .rightMouseUp) ? super.hitTest(point) : nil
    }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}

struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> RightClickView {
        let v = RightClickView(); v.onRightClick = action; return v
    }
    func updateNSView(_ v: RightClickView, context: Context) { v.onRightClick = action }
}

extension View {
    /// Menú con clic derecho que sí funciona en la isla.
    func islandMenu(_ items: @escaping () -> [PopupItem]) -> some View {
        background(RightClickCatcher { PopupMenu.show(items()) })
    }
}
