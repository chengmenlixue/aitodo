import SwiftUI
import UserNotifications

@main
struct AiTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup("待办") {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("切换视图") {
                    NotificationCenter.default.post(name: .toggleViewMode, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if ReminderCenter.isAvailable {
            UNUserNotificationCenter.current().delegate = self
        }
        if let path = ProcessInfo.processInfo.environment["AITODO_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Self.snapshot(to: path) }
            // 第二张：供运行中外部修改 defaults 后对比（验证皮肤即时切换）
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { Self.snapshot(to: path + ".t7") }
            // 同时写出窗口在 CGEvent 全局坐标系中的位置（供合成拖拽验证脚本定位）
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Self.writeWindowFrame() }
        }
    }

    /// 调试用：把主窗口内容渲染为 PNG（AITODO_SNAPSHOT=/path/to.png 时触发）
    static func snapshot(to path: String) {
        guard let contentView = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return }
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            DebugLog.write("快照已保存：\(path)")
        }
    }

    /// 调试用：把窗口位置换算成 CGEvent 坐标（左上原点）写入 /tmp/aitodo_frame.txt
    static func writeWindowFrame() {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let screen = NSScreen.main else { return }
        let frame = window.frame
        let cgX = frame.origin.x
        let cgY = screen.frame.height - frame.maxY
        let text = "\(Int(cgX)) \(Int(cgY)) \(Int(frame.width)) \(Int(frame.height))"
        try? text.write(to: URL(fileURLWithPath: "/tmp/aitodo_frame.txt"), atomically: true, encoding: .utf8)
        DebugLog.write("窗口 frame：\(text)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
