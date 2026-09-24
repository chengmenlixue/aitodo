import AppKit
import SwiftUI

extension Notification.Name {
    static let toggleViewMode = Notification.Name("aitodo.toggleViewMode")
}

struct RootView: View {
    @EnvironmentObject private var store: TaskStore
    @StateObject private var screenshot = ScreenshotManager.shared
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue
    @State private var draft = ProcessInfo.processInfo.environment["AITODO_DEMO_DRAFT"] ?? ""
    @State private var selectedQuadrant: Quadrant = .importantNotUrgent
    @State private var viewMode: ViewMode = .grid
    @State private var page: Page = ProcessInfo.processInfo.environment["AITODO_PAGE"] == "archive" ? .archive : .main

    private var skin: AppSkin { AppSkin.from(skinRaw) }

    private static let dateLineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 · EEEE"
        return formatter
    }()

    private var dateLine: String { Self.dateLineFormatter.string(from: Date()) }

    var body: some View {
        ZStack {
            if skin == .glass {
                VisualEffectBackdrop()
            }
            VStack(alignment: .leading, spacing: 16) {
                header
                if page == .main {
                    InputBar(text: $draft, selectedQuadrant: $selectedQuadrant) { addCurrent() }
                    Group {
                        switch viewMode {
                        case .grid: QuadrantGrid()
                        case .list: ListView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    footer
                } else {
                    ArchiveView(page: $page)
                }
            }
            .padding(EdgeInsets(top: 42, leading: 22, bottom: 14, trailing: 22))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            // 顶部隐形拖拽条：窗口只能从这里移动，避免与任务拖拽冲突
            WindowDragStrip()
                .frame(height: 44)
                .frame(maxWidth: .infinity)
        }
        .background(skin == .glass ? Color.clear : Theme.appBackground)
        .background(WindowAccessor())
        .onReceive(NotificationCenter.default.publisher(for: .toggleViewMode)) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                viewMode = viewMode == .grid ? .list : .grid
                page = .main
            }
        }
        .onChange(of: skinRaw) { _ in Self.applyAppAppearance() }
        .onAppear {
            // 启动即按已保存的皮肤设置系统外观（AppDelegate 默认深色，纯白皮肤需要纠正）
            Self.applyAppAppearance()
            FloatingBallManager.shared.start(store: store)
            RecognitionPanelController.shared.start(store: store)
            SmartReminderCenter.shared.start(store: store)
        }
    }

    /// 纯白皮肤使用浅色系统外观，弹窗/选择器才与界面一致
    static func applyAppAppearance() {
        let skin = AppSkin.from(UserDefaults.standard.string(forKey: "skin"))
        NSApp.appearance = NSAppearance(named: skin == .plain ? .aqua : .darkAqua)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateLine)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("待办")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Circle()
                        .fill(Theme.textTertiary)
                        .frame(width: 4, height: 4)
                }
            }
            Spacer()
            HeaderControls(page: $page, viewMode: $viewMode)
        }
    }

    private var footer: some View {
        HStack {
            Text("剩余 \(store.remainingCount) 项 · 共 \(store.totalCount) 项")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Button {
                store.clearCompleted()
            } label: {
                Text("清空已完成")
                    .font(.system(size: 13))
                    .foregroundColor(store.completedCount > 0 ? Theme.textSecondary : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(store.completedCount == 0)
        }
    }

    private func addCurrent() {
        let parsed = DueParser.parse(draft)
        store.add(title: parsed.title, quadrant: selectedQuadrant, dueDate: parsed.due)
        draft = ""
    }
}

/// 右上角控件组：归档 / 视图切换 / 设置
struct HeaderControls: View {
    @Binding var page: Page
    @Binding var viewMode: ViewMode

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                iconButton("archivebox",
                           active: page == .archive,
                           help: "归档") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        page = page == .archive ? .main : .archive
                    }
                }
                iconButton("list.bullet",
                           active: page == .main && viewMode == .list,
                           help: "列表视图") {
                    withAnimation(.easeInOut(duration: 0.15)) { viewMode = .list; page = .main }
                }
                iconButton("square.grid.2x2",
                           active: page == .main && viewMode == .grid,
                           help: "宫格视图") {
                    withAnimation(.easeInOut(duration: 0.15)) { viewMode = .grid; page = .main }
                }
            }
            .padding(4)
            .background(ChromeBackground(cornerRadius: 15))

            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(ChromeBackground(cornerRadius: 19))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    private func iconButton(_ icon: String, active: Bool, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(active ? Theme.actionForeground : Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(active ? Theme.actionButton : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// 窗口按皮肤配置透明度（毛玻璃需要透明窗口才能透出桌面模糊）
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.configure(nsView.window)
    }

    static func configure(_ window: NSWindow?) {
        guard let window else { return }
        installCloseInterceptor(on: window)
        let skin = AppSkin.from(UserDefaults.standard.string(forKey: "skin"))
        window.isOpaque = skin != .glass
        switch skin {
        case .glass:
            window.backgroundColor = .clear
        case .plain:
            window.backgroundColor = NSColor(srgbRed: 0xF7 / 255.0, green: 0xF7 / 255.0,
                                             blue: 0xF5 / 255.0, alpha: 1)
        case .classic:
            window.backgroundColor = NSColor(srgbRed: 0x0B / 255.0, green: 0x0B / 255.0,
                                             blue: 0x0C / 255.0, alpha: 1)
        }
    }

    /// 主窗口的 SwiftUI 代理包一层转发拦截：「关闭」（⌘W/红点）改为最小化到 Dock，
    /// 窗口对象不被销毁——应用常驻（悬浮球/菜单栏不退出），悬浮球或 Dock 图标可唤回。
    /// 转发兜底保证 SwiftUI 自身依赖的代理回调不受影响。
    private static var closeInterceptor: WindowCloseInterceptor?

    private static func installCloseInterceptor(on window: NSWindow) {
        guard !(window.delegate is WindowCloseInterceptor) else { return }
        DebugLog.write("安装主窗口关闭拦截器（原 delegate=\(String(describing: type(of: window.delegate)))）")
        let interceptor = WindowCloseInterceptor(original: window.delegate)
        // NSWindow.delegate 是弱引用：拦截器必须静态保活，否则赋值后立即释放
        closeInterceptor = interceptor
        window.delegate = interceptor
    }
}

private final class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    private weak var original: NSWindowDelegate?

    init(original: NSWindowDelegate?) {
        self.original = original
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? { original }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        DebugLog.write("windowShouldClose 拦截：title=\(sender.title)")
        // 「关闭」=隐藏窗口而非销毁：应用常驻（悬浮球/菜单栏不退出）。
        // 恢复只走 Dock 图标或菜单「显示待办窗口」——悬浮球点击不唤回（产品语义）
        sender.orderOut(nil)
        FloatingBallManager.shared.mainWindowDidCloseByCommand()
        return false
    }
}

/// 顶部隐形“标题栏”：按下即进入窗口拖动（performDrag 标准做法）
struct WindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragStripView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragStripView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
