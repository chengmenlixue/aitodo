import AppKit
import SwiftUI

/// 设置独立窗口（点击齿轮打开），外观跟随当前皮肤
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let skin = AppSkin.from(UserDefaults.standard.string(forKey: "skin"))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 680),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "设置"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 380, height: 560)
            switch skin {
            case .glass:
                window.isOpaque = false
                window.backgroundColor = .clear
            case .plain:
                window.backgroundColor = NSColor(srgbRed: 0xF7 / 255.0, green: 0xF7 / 255.0,
                                                 blue: 0xF5 / 255.0, alpha: 1)
            case .classic:
                window.backgroundColor = NSColor(srgbRed: 0x0B / 255.0, green: 0x0B / 255.0,
                                                 blue: 0x0C / 255.0, alpha: 1)
            }
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
