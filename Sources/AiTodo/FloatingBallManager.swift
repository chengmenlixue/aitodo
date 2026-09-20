import AppKit
import Combine
import SwiftUI

/// 桌面悬浮球 + 菜单栏四色数字：单例管理器
/// - 悬浮球：左键点色格弹出该象限待办面板（FloatingBallPopupView），点底衬开合主窗口，右键菜单，拖动持久化
/// - 弹出面板：贴着悬浮球弹出，可成 key window（快速输入需要键盘）但不激活应用
final class FloatingBallManager: NSObject, ObservableObject, NSMenuDelegate, NSWindowDelegate {
    static let shared = FloatingBallManager()

    static let ballSize = CGSize(width: 72, height: 72)
    private static let enabledKey = "floatingBallEnabled"
    private static let menuBarKey = "menuBarBadgeEnabled"
    private static let xKey = "floatingBallX"
    private static let yKey = "floatingBallY"

    /// 各象限未完成数，索引对应 Quadrant.rawValue
    @Published private(set) var quadrantCounts: [Int] = [0, 0, 0, 0]
    /// 悬停放大（由容器视图的 tracking area 驱动）
    @Published var ballHovered = false
    /// 悬停命中的色格（高亮提示可点击弹出）
    @Published var ballHoveredCell: Quadrant?
    /// 当前弹出面板对应的象限（nil = 面板未显示）
    @Published private(set) var popupQuadrant: Quadrant?
    /// 面板内「快速输入」行是否展开
    @Published var popupInputVisible = false
    /// 面板中展开详情的任务（nil = 无）
    @Published private(set) var expandedTaskID: UUID?
    /// 正在自定义截止时间的任务（详情内显示日期选择器）
    @Published var customDueTaskID: UUID?

    /// 「隐藏直到下次重启」：仅本次运行内隐藏，不落盘
    private var sessionHidden = false
    private var panel: FloatingBallPanel?
    private var popupPanel: FloatingPopupPanel?
    private var statusItem: NSStatusItem?
    private var store: TaskStore?
    private var tasksSubscription: AnyCancellable?
    private var popupMonitors: [Any] = []
    /// 程序性设框期间抑制 windowDidMove 的拖拽联动
    private var suppressPopupMoveObservation = false
    /// 面板最近一次已知原点（用户拖拽面板时据此算位移联动悬浮球）
    private var lastPopupOrigin = CGPoint.zero
    /// 开始拖球时记录的面板原点（拖球时面板跟随）
    private var popupOriginAtBallDragStart: CGPoint?
    private var kvoContext = 0

    private var ballEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Self.enabledKey) == nil
            ? true
            : defaults.bool(forKey: Self.enabledKey)
    }

    private var menuBarEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Self.menuBarKey) == nil
            ? true
            : defaults.bool(forKey: Self.menuBarKey)
    }

    // MARK: - 启动与订阅

    /// 由 RootView.onAppear 调用，幂等
    func start(store: TaskStore) {
        guard self.store == nil else { return }
        self.store = store

        let defaults = UserDefaults.standard
        defaults.addObserver(self, forKeyPath: Self.enabledKey, options: [], context: &kvoContext)
        defaults.addObserver(self, forKeyPath: Self.menuBarKey, options: [], context: &kvoContext)

        tasksSubscription = store.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCounts()
                self?.refreshPopupFrame()
            }

        makePanelIfNeeded()
        refreshBallVisibility()
        refreshStatusItem()
        refreshCounts()
    }

    private func refreshCounts() {
        guard let store else { return }
        quadrantCounts = store.pendingCountsByQuadrant
        statusItem?.button?.image = Self.renderStatusImage(counts: quadrantCounts)
    }

    // MARK: - 悬浮球面板

    private func makePanelIfNeeded() {
        guard panel == nil else { return }
        let frame = NSRect(origin: restoredOrigin(), size: Self.ballSize)
        let ballPanel = FloatingBallPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        ballPanel.level = .floating
        ballPanel.isOpaque = false
        ballPanel.backgroundColor = .clear
        ballPanel.hasShadow = false
        ballPanel.hidesOnDeactivate = false
        ballPanel.isMovableByWindowBackground = false
        ballPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ballPanel.ignoresMouseEvents = false

        let container = FloatingBallContainerView(frame: NSRect(origin: .zero, size: Self.ballSize))
        container.manager = self
        let hosting = NSHostingView(rootView: FloatingBallView(manager: self))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        ballPanel.contentView = container
        panel = ballPanel
    }

    private func restoredOrigin() -> CGPoint {
        let defaults = UserDefaults.standard
        let visible = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // 首次默认：主屏可视区右下角 20pt
        let fallback = CGPoint(x: visible.maxX - Self.ballSize.width - 20, y: visible.minY + 20)
        guard let x = defaults.object(forKey: Self.xKey) as? Double,
              let y = defaults.object(forKey: Self.yKey) as? Double else { return fallback }
        return clampOrigin(CGPoint(x: x, y: y))
    }

    /// 把悬浮球原点约束进所在屏幕可视区（屏幕拔掉/分辨率变更后不丢球）
    func clampOrigin(_ origin: CGPoint) -> CGPoint {
        let candidate = NSRect(origin: origin, size: Self.ballSize)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(candidate) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        let x = min(max(origin.x, visible.minX + 8), visible.maxX - Self.ballSize.width - 8)
        let y = min(max(origin.y, visible.minY + 8), visible.maxY - Self.ballSize.height - 8)
        return CGPoint(x: x, y: y)
    }

    func persistBallPosition(_ origin: CGPoint?) {
        guard let origin else { return }
        let defaults = UserDefaults.standard
        defaults.set(Double(origin.x), forKey: Self.xKey)
        defaults.set(Double(origin.y), forKey: Self.yKey)
    }

    private func refreshBallVisibility() {
        guard let panel else { return }
        if ballEnabled && !sessionHidden {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            closePopup()
            panel.orderOut(nil)
        }
    }

    // MARK: - 主窗口开关

    private var mainWindow: NSWindow? {
        NSApp.windows.first { !($0 is NSPanel) && $0.title == "待办" }
    }

    private var mainWindowHidden: Bool {
        guard let window = mainWindow else { return true }
        return window.isMiniaturized || !window.isVisible
    }

    /// 隐藏必须用 miniaturize（不能用 orderOut，会触发「最后一个窗口关闭」导致 App 退出）
    func toggleMainWindow() {
        closePopup()
        guard let window = mainWindow else { return }
        if window.isMiniaturized || !window.isVisible {
            showMainWindow()
        } else {
            window.miniaturize(nil)
        }
    }

    private func showMainWindow() {
        guard let window = mainWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 色格弹出面板

    func togglePopup(for quadrant: Quadrant) {
        if popupQuadrant == quadrant {
            closePopup()
            return
        }
        openPopup(quadrant)
    }

    private func openPopup(_ quadrant: Quadrant) {
        guard let store, let ballPanel = panel else { return }
        popupInputVisible = false
        expandedTaskID = nil
        customDueTaskID = nil
        popupQuadrant = quadrant
        let popup = ensurePopupPanel()
        let view = FloatingBallPopupView(manager: self, store: store, quadrant: quadrant)
        if let hosting = popup.contentView as? NSHostingView<FloatingBallPopupView> {
            hosting.rootView = view
        } else {
            popup.contentView = NSHostingView(rootView: view)
        }
        positionPopup(popup, ballFrame: ballPanel.frame)
        popup.orderFrontRegardless()
        installPopupMonitors()
        DebugLog.write("弹出面板 frame=\(NSStringFromRect(popup.frame)) q=\(quadrant.rawValue)")
    }

    private func ensurePopupPanel() -> FloatingPopupPanel {
        if let popupPanel { return popupPanel }
        let popup = FloatingPopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        popup.level = .floating
        popup.isOpaque = false
        popup.backgroundColor = .clear
        popup.hasShadow = false
        popup.hidesOnDeactivate = false
        popup.isMovableByWindowBackground = true   // 头部/空白区可直接拖动，悬浮球跟随联动
        popup.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        popup.delegate = self
        popupPanel = popup
        return popup
    }

    /// 默认贴在悬浮球左侧、顶边对齐；贴不下放右侧，垂直方向约束进屏幕
    private func positionPopup(_ popup: NSPanel, ballFrame: NSRect) {
        let height = popupHeight()
        let width = PopupMetrics.width
        let visible = (NSScreen.screens.first { $0.visibleFrame.intersects(ballFrame) }
            ?? NSScreen.main)?.visibleFrame ?? ballFrame
        var x = ballFrame.minX - width - 10
        if x < visible.minX + 8 { x = ballFrame.maxX + 10 }
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        var y = ballFrame.maxY - height
        y = min(max(y, visible.minY + 8), visible.maxY - height - 8)
        setPopupFrame(NSRect(x: x, y: y, width: width, height: height))
    }

    /// 面板当前应有高度（顶边固定，内容增减时只改底边）；展开详情的行追加详情高度
    private func popupHeight() -> CGFloat {
        guard let popupQuadrant, let store else {
            return PopupMetrics.height(itemCount: 0, inputVisible: popupInputVisible)
        }
        let pending = store.tasks(in: popupQuadrant).filter { !$0.isDone }
        var detail: CGFloat = 0
        if let expandedTaskID,
           pending.count <= PopupMetrics.maxVisibleRows,
           let task = pending.first(where: { $0.id == expandedTaskID }) {
            detail = PopupMetrics.detailHeight(subtaskCount: task.subtasks.count)
            if customDueTaskID == expandedTaskID {
                detail += PopupMetrics.customDueHeight
            }
        }
        return PopupMetrics.height(itemCount: pending.count, inputVisible: popupInputVisible, detail: detail)
    }

    private func refreshPopupFrame() {
        guard let popupPanel, popupPanel.isVisible else { return }
        let newHeight = popupHeight()
        var frame = popupPanel.frame
        guard abs(frame.height - newHeight) > 0.5 else { return }
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight
        setPopupFrame(frame)
        DebugLog.write("弹出面板 frame=\(NSStringFromRect(frame)) 刷新")
    }

    /// 统一的面板设框入口：程序性移动不触发 windowDidMove 的拖拽联动
    private func setPopupFrame(_ frame: NSRect) {
        guard let popupPanel else { return }
        suppressPopupMoveObservation = true
        popupPanel.setFrame(frame, display: true)
        suppressPopupMoveObservation = false
        lastPopupOrigin = frame.origin
    }

    // MARK: - 面板⇄悬浮球拖拽联动

    /// 用户拖动面板：悬浮球跟随同一位移（windowDidMove 逐帧回调）
    func windowDidMove(_ notification: Notification) {
        guard !suppressPopupMoveObservation,
              let popupPanel, (notification.object as? NSWindow) === popupPanel,
              let ballPanel = panel else { return }
        let newOrigin = popupPanel.frame.origin
        let dx = newOrigin.x - lastPopupOrigin.x
        let dy = newOrigin.y - lastPopupOrigin.y
        lastPopupOrigin = newOrigin
        guard dx != 0 || dy != 0 else { return }
        let ballOrigin = ballPanel.frame.origin
        let moved = clampOrigin(CGPoint(x: ballOrigin.x + dx, y: ballOrigin.y + dy))
        ballPanel.setFrameOrigin(moved)
        persistBallPosition(moved)
    }

    /// 拖球开始：记下面板原点，拖动期间面板跟随同一位移
    func ballDragWillBegin() {
        popupOriginAtBallDragStart = popupPanel?.frame.origin
    }

    /// 拖球进行中：面板跟随
    func ballDragMoved(totalDX: CGFloat, totalDY: CGFloat) {
        guard let popupPanel, popupPanel.isVisible, let start = popupOriginAtBallDragStart else { return }
        var frame = popupPanel.frame
        frame.origin = CGPoint(x: start.x + totalDX, y: start.y + totalDY)
        setPopupFrame(frame)
    }

    func closePopup() {
        guard popupPanel?.isVisible == true || popupQuadrant != nil else { return }
        popupPanel?.orderOut(nil)
        popupQuadrant = nil
        popupInputVisible = false
        expandedTaskID = nil
        customDueTaskID = nil
        removePopupMonitors()
    }

    /// 行点击展开/收起详情（再点同一行收起）
    func setExpandedTask(_ id: UUID?) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
        if expandedTaskID != id { customDueTaskID = nil }
        refreshPopupFrame()
    }

    /// 「自定义…」截止时间：展开该行详情并切换内嵌日期选择器
    func toggleCustomDue(_ id: UUID) {
        if customDueTaskID == id {
            customDueTaskID = nil
        } else {
            expandedTaskID = id
            customDueTaskID = id
        }
        refreshPopupFrame()
    }

    /// 行内编辑需要键盘：激活应用并让面板成为 key
    func activatePopupForEditing() {
        NSApp.activate(ignoringOtherApps: true)
        popupPanel?.makeKey()
    }

    /// 展开/收起快速输入行；展开时激活应用并让面板成为 key（键盘输入需要）
    func togglePopupInput() {
        popupInputVisible.toggle()
        if popupInputVisible {
            NSApp.activate(ignoringOtherApps: true)
            popupPanel?.makeKey()
        }
        refreshPopupFrame()
    }

    /// 面板上的截图识别：先收起面板，结果在独立浮动面板展示（不呼出主窗口）
    func triggerScreenshotFromPopup() {
        guard ScreenshotManager.shared.phase == .idle else { return }
        closePopup()
        ScreenshotManager.shared.trigger()
    }

    // MARK: - 弹出面板的点击外部关闭

    private func installPopupMonitors() {
        guard popupMonitors.isEmpty else { return }
        popupMonitors.append(NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.closePopup() }
        })
        popupMonitors.append(NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            // 球本身的左键按下不关面板：开/关在容器 mouseUp 才决策（点击开合、拖拽时面板跟随）
            if event.window === self.panel { return event }
            // 面板内的下拉菜单（如截止时间）是独立菜单窗口，不算点外部
            if event.window !== self.popupPanel, !Self.isMenuWindow(event.window) {
                self.closePopup()
            }
            return event
        })
        popupMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            if Self.isMenuWindow(event.window) { return event }   // 菜单打开时 Esc 交给菜单
            // Esc：输入行展开时先收输入行，否则关面板
            if self.popupInputVisible {
                self.togglePopupInput()
            } else {
                self.closePopup()
            }
            return nil
        })
    }

    /// 菜单窗口（NSMenuWindowManagerWindow 等）不做「点外部关闭」判定
    private static func isMenuWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return String(describing: type(of: window)).contains("Menu")
    }

    private func removePopupMonitors() {
        for monitor in popupMonitors {
            NSEvent.removeMonitor(monitor)
        }
        popupMonitors.removeAll()
    }

    // MARK: - 右键菜单（悬浮球）

    func buildBallMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(mainWindowHidden ? "显示待办窗口" : "隐藏待办窗口",
                              action: #selector(toggleMainWindowAction)))
        menu.addItem(menuItem("截图识别待办", action: #selector(screenshotAction)))
        menu.addItem(.separator())
        menu.addItem(menuItem("隐藏直到下次重启", action: #selector(hideBallForSessionAction)))
        menu.addItem(menuItem("停用桌面悬浮球", action: #selector(disableBallAction)))
        return menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleMainWindowAction() { toggleMainWindow() }
    @objc private func screenshotAction() { ScreenshotManager.shared.trigger() }

    @objc private func hideBallForSessionAction() {
        sessionHidden = true
        refreshBallVisibility()
    }

    @objc private func disableBallAction() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    // MARK: - 菜单栏四色数字

    private func refreshStatusItem() {
        if menuBarEnabled {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = Self.renderStatusImage(counts: quadrantCounts)
            item.button?.imageScaling = .scaleNone
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
            DebugLog.write("菜单栏数字：statusItem 已创建，button=\(item.button != nil)，image尺寸=\(item.button?.image?.size.debugDescription ?? "nil")")
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// 每次点开前重建，保证「显示/隐藏」等标题随状态变化
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(menuItem(mainWindowHidden ? "显示待办窗口" : "隐藏待办窗口",
                              action: #selector(toggleMainWindowAction)))
        menu.addItem(menuItem("截图识别待办", action: #selector(screenshotAction)))
        menu.addItem(.separator())
        menu.addItem(menuItem(ballEnabled ? "隐藏桌面悬浮球" : "显示桌面悬浮球",
                              action: #selector(toggleBallAction)))
        menu.addItem(menuItem("隐藏菜单栏数字", action: #selector(hideMenuBarAction)))
    }

    @objc private func toggleBallAction() {
        UserDefaults.standard.set(!ballEnabled, forKey: Self.enabledKey)
    }

    @objc private func hideMenuBarAction() {
        UserDefaults.standard.set(false, forKey: Self.menuBarKey)
    }

    /// 菜单栏迷你四色分格：2×2 色格各带象限数字（Retina 按主屏倍率绘制）
    private static func renderStatusImage(counts: [Int]) -> NSImage {
        let cell: CGFloat = 9.5, gap: CGFloat = 1, radius: CGFloat = 3
        let size = NSSize(width: cell * 2 + gap, height: cell * 2 + gap)
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return NSImage(size: size) }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // NSImage 上下文为左下原点：第一行（红/绿）画在上方
        let cells: [(quadrant: Quadrant, origin: CGPoint)] = [
            (.urgentImportant, CGPoint(x: 0, y: cell + gap)),
            (.importantNotUrgent, CGPoint(x: cell + gap, y: cell + gap)),
            (.urgentNotImportant, CGPoint(x: 0, y: 0)),
            (.neither, CGPoint(x: cell + gap, y: 0)),
        ]
        for entry in cells {
            let count = counts.indices.contains(entry.quadrant.rawValue) ? counts[entry.quadrant.rawValue] : 0
            let rect = NSRect(origin: entry.origin, size: NSSize(width: cell, height: cell))
            let hex = entry.quadrant.accentHex
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: count == 0 ? 0.45 : 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

            let label = count > 99 ? "99" : "\(count)"
            let text = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 6.5, weight: .bold),
                .foregroundColor: NSColor.white,
            ])
            let textSize = text.size()
            text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - UserDefaults KVO

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard context == &kvoContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        switch keyPath {
        case Self.enabledKey:
            refreshBallVisibility()
        case Self.menuBarKey:
            refreshStatusItem()
        default:
            break
        }
    }
}

/// 无边框非激活面板：canBecomeKey=false，点击不抢焦点
final class FloatingBallPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// 弹出面板：.nonactivatingPanel 点击本身不激活应用，但可成 key window（快速输入需要键盘）
final class FloatingPopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 事件容器：命中只认中心 62×62 区域（四角透明穿透），鼠标事件一律由容器处理（不落入 SwiftUI）
final class FloatingBallContainerView: NSView {
    weak var manager: FloatingBallManager?

    private var pressGlobal = CGPoint.zero
    private var windowOrigin = CGPoint.zero
    private var hasDragged = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        // 本视图只作为窗口 contentView 使用（superview 为 nil），point 即窗口坐标
        guard bounds.insetBy(dx: 5, dy: 5).contains(point) else { return nil }
        return self
    }

    /// 命中点落在哪个色格（顶左坐标：色格区 8..64，每格 27、间距 2）；nil = 底衬/间隙（主窗口开关区）
    func quadrant(at point: NSPoint) -> Quadrant? {
        let flippedY = bounds.height - point.y
        guard point.x >= 8, point.x <= 64, flippedY >= 8, flippedY <= 64 else { return nil }
        let col = point.x < 36 ? 0 : 1
        let row = flippedY < 36 ? 0 : 1
        switch (row, col) {
        case (0, 0): return .urgentImportant
        case (0, 1): return .importantNotUrgent
        case (1, 0): return .urgentNotImportant
        default: return .neither
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds.insetBy(dx: 5, dy: 5), cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds.insetBy(dx: 5, dy: 5),
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        manager?.ballHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        manager?.ballHovered = false
        manager?.ballHoveredCell = nil
    }

    override func mouseMoved(with event: NSEvent) {
        manager?.ballHoveredCell = quadrant(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        pressGlobal = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin ?? .zero
        hasDragged = false
        manager?.ballDragWillBegin()
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - pressGlobal.x
        let dy = current.y - pressGlobal.y
        if !hasDragged && (dx * dx + dy * dy) <= 3 * 3 { return }
        hasDragged = true
        let origin = CGPoint(x: windowOrigin.x + dx, y: windowOrigin.y + dy)
        window?.setFrameOrigin(manager?.clampOrigin(origin) ?? origin)
        manager?.ballDragMoved(totalDX: dx, totalDY: dy)
    }

    override func mouseUp(with event: NSEvent) {
        defer { hasDragged = false }
        if hasDragged {
            manager?.persistBallPosition(window?.frame.origin)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let quadrant = quadrant(at: point) {
            manager?.togglePopup(for: quadrant)
        } else {
            manager?.toggleMainWindow()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let manager else { return }
        manager.closePopup()   // 右键菜单接管，先收起面板
        let menu = manager.buildBallMenu()
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
}
