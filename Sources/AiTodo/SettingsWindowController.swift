import AppKit
import SwiftUI

/// 设置独立窗口（点击齿轮打开，替代原气泡面板）
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 640),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "设置"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 380, height: 560)
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
