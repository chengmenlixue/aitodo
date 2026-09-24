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
        ScreenshotManager.shared.registerHotkey()
        if ProcessInfo.processInfo.environment["AITODO_TEST_REMINDER"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Self.fireTestReminder() }
        }
        if let path = ProcessInfo.processInfo.environment["AITODO_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Self.snapshot(to: path) }
            // 第二张：供运行中外部修改 defaults 后对比（验证皮肤即时切换）
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { Self.snapshot(to: path + ".t7") }
            // 同时写出窗口在 CGEvent 全局坐标系中的位置（供合成拖拽验证脚本定位）
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Self.writeWindowFrame() }
        }
        if ProcessInfo.processInfo.environment["AITODO_TEST_CLOSE"] != nil {
            // 调试用：对主窗口执行 performClose（验证「关闭=隐藏窗口、应用常驻」）
            // 启动基线（+2s）：正常显示状态下 occlusion 是否会报 visible（区分环境因素与代码缺陷）
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let w = NSApp.windows.first { !($0 is NSPanel) && $0.title == "待办" }
                DebugLog.write("启动基线：window=\(w != nil) occlusionVisible=\(w?.occlusionState.contains(.visible) ?? false)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Self.testClose() }
        }
        if ProcessInfo.processInfo.environment["AITODO_TEST_QUIT"] != nil {
            // 调试用：4 秒后执行 NSApp.terminate（验证「退出待办」链路是否可靠）
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                DebugLog.write("测试退出：NSApp.terminate")
                NSApp.terminate(nil)
                // 若 terminate 未完成（被挂起），2 秒后兜底强退，保证退出永不失效
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    DebugLog.write("测试退出：terminate 未完成，兜底 exit")
                    exit(0)
                }
            }
        }
        if ProcessInfo.processInfo.environment["AITODO_TEST_SMART_REMINDER"] != nil {
            // 调试用：启动 5 秒后强制触发一次 AI 智能提醒（验证 AI 链路与通知横幅）
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                Task { _ = await SmartReminderCenter.shared.summarizeNowManually() }
            }
        }
        if ProcessInfo.processInfo.environment["AITODO_TEST_RECOGNITION"] != nil {
            // 调试用：跳过截图流程直接注入识别结果弹出确认面板（验证面板交互）
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                ScreenshotManager.shared.resultTasks = [
                    ParsedTask(title: "将云数据素材补充完整", quadrant: .importantNotUrgent),
                    ParsedTask(title: "修复企业知识库删除同步 bug", quadrant: .importantNotUrgent)
                ]
                ScreenshotManager.shared.phase = .results
            }
            // +3s：面板落位后把 frame 写成 CG 全局坐标（顶左原点），供合成点击定位
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let panel = NSApp.windows.first(where: { $0 is RecognitionPanel }),
                      let screen = NSScreen.main else { return }
                let frame = panel.frame
                let text = "\(Int(frame.origin.x)) \(Int(screen.frame.height - frame.maxY)) \(Int(frame.width)) \(Int(frame.height))"
                try? text.write(toFile: "/tmp/aitodo_recognition_frame.txt", atomically: true, encoding: .utf8)
                DebugLog.write("识别面板 frame(CG)：\(text) appActive=\(NSApp.isActive)")
            }
        }
    }

    /// 应用被激活（如识别结果面板 NSApp.activate）时的副作用防御：
    /// ⌘W 关闭的主窗口不被悄悄带回屏幕
    func applicationDidBecomeActive(_ notification: Notification) {
        FloatingBallManager.shared.reassertMainWindowHidden()
    }

    /// 调试用：AITODO_TEST_CLOSE=1 启动时触发主窗口关闭流程
    static func testClose() {
        let window = NSApp.windows.first { !($0 is NSPanel) && $0.title == "待办" }
        DebugLog.write("测试关闭：window=\(window != nil) delegate=\(String(describing: type(of: window?.delegate)))")
        window?.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // 验证关闭后悬浮球点击（toggleMainWindow）不唤回窗口
            FloatingBallManager.shared.toggleMainWindow()
            DebugLog.write("关闭后 toggleMainWindow：isVisible=\(window?.isVisible ?? false)（期望 false=不唤回）")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            DebugLog.write("测试关闭后：window存活=\(window != nil) visible=\(window?.isVisible ?? false) mini=\(window?.isMiniaturized ?? false) occlusionVisible=\(window?.occlusionState.contains(.visible) ?? false)")
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

    /// 应用常驻：主窗口「关闭」被拦截为最小化（见 WindowCloseInterceptor），
    /// 此处兜底——即使窗口被程序性 close 也不退出，悬浮球/菜单栏保持在线
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 点击 Dock 图标：主窗口不在屏时恢复显示。
    /// 注意 flag 不可信：SwiftUI 窗口最小化后仍上报 isVisible=true（flag=true），
    /// 因此忽略 flag，总是做一次 occlusion 感知的恢复尝试（窗口在屏时为无害 no-op）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DebugLog.write("applicationShouldHandleReopen: flag=\(flag)")
        if FloatingBallManager.shared.restoreMainWindow() {
            return false
        }
        return true
    }

    /// 调试用：AITODO_TEST_REMINDER=1 启动时排一条 5 秒后的测试通知（验证横幅图标）
    static func fireTestReminder() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DebugLog.write("通知权限：authorization=\(s.authorizationStatus.rawValue) alert=\(s.alertSetting.rawValue) notifCenter=\(s.notificationCenterSetting.rawValue)")
        }
        let content = UNMutableNotificationContent()
        content.title = "待办提醒（图标测试）"
        content.body = "这是 5 秒后触发的测试通知"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "aitodo.test-reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
        DebugLog.write("测试通知已排定（5s 后）")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DebugLog.write("前台通知 willPresent：\(notification.request.content.title)")
        // AI 总结在前台用应用内横幅展示（时长可控、带图标），系统侧只进通知中心存档；
        // 其余通知（待办提醒等）维持系统横幅
        if notification.request.identifier == ReminderCenter.summaryIdentifier {
            completionHandler([.list])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    /// 点击通知横幅：打开主窗口。须走 restoreMainWindow（内部处理 ⌘W 关闭防御与
    /// deminiaturize），直接 NSApp.activate 会被 applicationDidBecomeActive 压回
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DebugLog.write("通知点击：\(response.notification.request.identifier)")
        FloatingBallManager.shared.restoreMainWindow()
        completionHandler()
    }
}
