import AppKit
import SwiftUI

/// 设置独立窗口（点击齿轮打开），外观跟随当前皮肤（皮肤变更后重开设置窗口即生效）
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var windowSkin: AppSkin?

    func show() {
        let skin = AppSkin.from(UserDefaults.standard.string(forKey: "skin"))
        if let window {
            if windowSkin != skin {
                applySkin(skin, to: window)
                windowSkin = skin
            }
        } else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 680),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "设置"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 380, height: 560)
            applySkin(skin, to: window)
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
            windowSkin = skin
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applySkin(_ skin: AppSkin, to window: NSWindow) {
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
    }
}
