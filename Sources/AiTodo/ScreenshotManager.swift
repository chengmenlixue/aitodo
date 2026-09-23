import AppKit
import Carbon.HIToolbox
import CoreGraphics
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

final class ScreenshotManager: ObservableObject {
    static let shared = ScreenshotManager()

    enum Phase: Equatable {
        case idle
        case recognizing
        case results
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var resultTasks: [ParsedTask] = []
    @Published var lastError: String?

    private let selection = SelectionCoordinator()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private(set) var hotkeyRegisterStatus: OSStatus = noErr

    // MARK: - 快捷键

    func registerHotkey() {
        let defaults = UserDefaults.standard
        let code = (defaults.object(forKey: "shotKeyCode") as? Int) ?? 1            // kVK_ANSI_S
        let nsMods = (defaults.object(forKey: "shotModifiers") as? Int) ?? 1572864 // ⌘⌥（NSEvent 格式）
        hotkeyRegisterStatus = HotKeyCenter.shared.register(keyCode: UInt32(code),
                                                            modifiers: carbonModifiers(fromNS: nsMods)) { [weak self] in
            DispatchQueue.main.async { self?.trigger() }
        }
    }

    var hotkeyRegistered: Bool { hotkeyRegisterStatus == noErr }

    /// NSEvent.ModifierFlags.rawValue → Carbon 修饰键掩码（RegisterEventHotKey 使用）
    private func carbonModifiers(fromNS nsRaw: Int) -> UInt32 {
        var carbon: UInt32 = 0
        if nsRaw & 1 << 20 != 0 { carbon |= UInt32(cmdKey) }       // ⌘  256
        if nsRaw & 1 << 19 != 0 { carbon |= UInt32(optionKey) }    // ⌥ 2048
        if nsRaw & 1 << 18 != 0 { carbon |= UInt32(controlKey) }   // ⌃ 4096
        if nsRaw & 1 << 17 != 0 { carbon |= UInt32(shiftKey) }     // ⇧  512
        return carbon
    }

    func reapplyHotkey() {
        registerHotkey()
    }

    // MARK: - 主流程

    func trigger() {
        DebugLog.write("trigger 进入：phase=\(phase) screenCapturePermission=\(CGPreflightScreenCaptureAccess())")
        guard phase == .idle else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            lastError = "需要「屏幕录制」权限：系统设置 → 隐私与安全性 → 屏幕录制，勾选本应用后重试"
            phase = .failed(lastError!)
            return
        }
        selection.begin { [weak self] imageData in
            DispatchQueue.main.async { self?.handleCapture(imageData) }
        }
    }

    private func handleCapture(_ imageData: Data?) {
        guard let data = imageData else {
            // 截图失败不静默：给出可见的错误卡片（捕获/裁剪环节的失败原因会同时写入调试日志）
            lastError = "未能捕获屏幕内容，请重试；若反复出现，请带着 AITODO_DEBUG=1 的日志反馈"
            phase = .failed(lastError!)
            return
        }
        phase = .recognizing
        Task {
            do {
                let tasks = try await AITaskParser.parseTasks(imagePNG: data)
                await MainActor.run {
                    if tasks.isEmpty {
                        self.lastError = "截图中未识别到待办任务"
                        self.phase = .failed(self.lastError!)
                    } else {
                        self.resultTasks = tasks
                        self.phase = .results
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func dismissResults() {
        resultTasks = []
        phase = .idle
    }

    func dismissError() {
        lastError = nil
        phase = .idle
    }
}

// MARK: - 全局快捷键（Carbon，无第三方依赖）

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> OSStatus {
        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let hotKeyID = EventHotKeyID(signature: OSType(0x41495448), id: 1)  // 'AITH'

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData!).takeUnretainedValue()
            center.handler?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        DebugLog.write("RegisterEventHotKey(\(keyCode), mods=\(modifiers)) → \(status)")
        return status
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}

// MARK: - 选区覆盖窗协调

/// 选区遮罩面板：非激活面板（NSPanel）才能以未激活应用身份进入全屏 Space——
/// 普通 NSWindow 在应用未激活时会被窗口服务器排除在全屏 Space 之外（悬浮球一直可见即此原理）
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class SelectionCoordinator {
    private var windows: [NSWindow] = []
    private var escMonitor: Any?
    private var globalEscMonitor: Any?
    private var cancelHandler: (() -> Void)?

    func begin(onComplete: @escaping (Data?) -> Void) {
        close()
        // Esc 取消：覆盖窗不激活应用，热键触发时本应用通常在后台——
        // 本地监视器覆盖应用活跃时（点过覆盖窗后），全局监视器覆盖后台时的按键
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancelHandler?()
            return nil
        }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async { self?.cancelHandler?() }
        }
        cancelHandler = { [weak self] in
            self?.close()
            onComplete(nil)
        }
        let screens = NSScreen.screens
        DebugLog.write("选区遮罩：\(screens.count) 块屏幕，frames=\(screens.map { NSStringFromRect($0.frame) })")
        for screen in screens {
            // 不传 screen: 提示（canJoinAllSpaces 面板按 frame 落位即可，显式提示在某些
            // 多屏配置下会把面板钉在单屏的 Space 上，导致副屏不显示）
            let panel = OverlayPanel(contentRect: screen.frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered,
                                     defer: false)
            // 层级高于全屏应用窗口与菜单栏：shielding 是系统截图类工具选区遮罩的标准层级
            panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            // canJoinAllSpaces+fullScreenAuxiliary：遮罩出现在每个显示器/每个 Space（含全屏 Space）
            // stationary：不被调度中心/Exposé 干扰
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.ignoresMouseEvents = false

            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onComplete = { [weak self] viewRect in
                let displayID = screen.displayID
                // 关键：覆盖窗铺满该显示器，选区坐标即显示器本地坐标（顶部原点）。
                // 不能叠加 screen.frame.minX 等全局偏移，否则拓展屏选区越界导致截图失败。
                let bounds = CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height)
                let sourceRect = bounds.intersection(viewRect)
                let pixelScale = screen.backingScaleFactor
                DebugLog.write("选区完成：displayID=\(displayID) rect=\(NSStringFromRect(sourceRect)) scale=\(pixelScale)")
                self?.close()
                Task { @MainActor in
                    do {
                        let image = try await CaptureDisplay.image(displayID: displayID,
                                                                   sourceRect: sourceRect,
                                                                   pixelScale: pixelScale)
                        let data = CaptureImageTool.png(from: image, maxLongSide: 1600)
                        DebugLog.write("捕获成功：displayID=\(displayID) PNG=\(data?.count ?? 0) 字节")
                        onComplete(data)
                    } catch {
                        DebugLog.write("截图失败：\(error.localizedDescription)")
                        onComplete(nil)
                    }
                }
            }
            view.onCancel = { [weak self] in
                self?.cancelHandler?()
            }
            panel.contentView = view
            // orderFrontRegardless：不激活应用、不抢焦点，其他应用界面截图不跳动
            panel.orderFrontRegardless()
            // 随即建 key：nonactivatingPanel 建 key 不会激活应用，先把"窗口未建 key
            // 时首个 mouseDown 被消耗在建 key 上"这个坑绕开（首点拉不出选区的根源）。
            // 多屏时只有最后一块保持 key，其余面板靠 SelectionOverlayView 的
            // acceptsFirstMouse 兜底
            panel.makeKeyAndOrderFront(nil)
            windows.append(panel)
        }
        // 窗口服务器落位后统一再压一次前台：修复副屏面板首次落位被吞的竞态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.windows.forEach { $0.orderFrontRegardless() }
        }
        // 落位后复核：每块遮罩的实际状态（诊断拓展屏不出遮罩）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            for (index, panel) in self.windows.enumerated() {
                DebugLog.write("遮罩[\(index)]: frame=\(NSStringFromRect(panel.frame)) visible=\(panel.isVisible) screen=\(panel.screen?.localizedName ?? "nil") level=\(panel.level.rawValue)")
            }
        }
    }

    func close() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        if let monitor = globalEscMonitor {
            NSEvent.removeMonitor(monitor)
            globalEscMonitor = nil
        }
        cancelHandler = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

}

// MARK: - 屏幕截图（ScreenCaptureKit，macOS 13 及以下回退 CGDisplayCreateImage + 选区裁剪）
// 注：CGDisplayCreateImage 在 SDK 中标注 obsoleted=15.0，因此编译目标必须是 13.0/14.x；
// 若目标 ≥ 15.0（如不传 -target 用宿主机默认），该调用会直接编译报错。

enum CaptureDisplay {
    static func image(displayID: CGDirectDisplayID, sourceRect: CGRect, pixelScale: CGFloat) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            return try await screenCaptureKitImage(displayID: displayID, sourceRect: sourceRect, pixelScale: pixelScale)
        }
        return try legacyDisplayImage(displayID: displayID, sourceRect: sourceRect)
    }

    @available(macOS 14.0, *)
    private static func screenCaptureKitImage(displayID: CGDirectDisplayID, sourceRect: CGRect, pixelScale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw AIError(message: "未找到目标显示器")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int(sourceRect.width * pixelScale)
        config.height = Int(sourceRect.height * pixelScale)
        config.showsCursor = false
        config.captureResolution = .best
        config.queueDepth = 1
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// 选区坐标为显示器本地坐标（顶部原点），整屏截取后按像素密度裁剪
    private static func legacyDisplayImage(displayID: CGDirectDisplayID, sourceRect: CGRect) throws -> CGImage {
        guard let full = CGDisplayCreateImage(displayID) else {
            throw AIError(message: "未找到目标显示器")
        }
        let scale = CGFloat(full.width) / CGDisplayBounds(displayID).width   // 实际像素密度（1x/2x）
        let cropRect = CGRect(x: sourceRect.minX * scale,
                              y: sourceRect.minY * scale,
                              width: sourceRect.width * scale,
                              height: sourceRect.height * scale)
        guard let cropped = full.cropping(to: cropRect) else {
            throw AIError(message: "屏幕选区裁剪失败")
        }
        return cropped
    }
}

// MARK: - 选区覆盖视图

final class SelectionOverlayView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: () -> Void = {}

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }   // 顶部原点，截图换算更直观

    // 热键触发时本应用通常在后台：NSView 默认不接受"未激活窗口上的第一击"，
    // 该 mouseDown 被消耗在建 key 上而不下发给视图——即第一次点击拉不出选区。
    // 返回 true 让首击直接进入 mouseDown（第二重保险，覆盖未成为 key 的那块屏）
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        DebugLog.write("选区 mouseDown：\(NSStringFromPoint(point)) windowKey=\(window?.isKeyWindow ?? false)")
        startPoint = point
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint, let current = currentPoint else { onCancel(); return }
        let rect = rectBetween(start, current)
        guard rect.width >= 24, rect.height >= 24 else { onCancel(); return }
        onComplete?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard let start = startPoint, let current = currentPoint else { return }
        let rect = rectBetween(start, current)
        // 挖空选区露出桌面
        NSGraphicsContext.current?.cgContext.clear(rect)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        path.lineWidth = 1.5
        path.stroke()

        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(at: NSPoint(x: rect.minX, y: rect.minY - 22))
    }

    private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

// MARK: - 图像工具

enum CaptureImageTool {
    static func png(from image: CGImage, maxLongSide: CGFloat) -> Data? {
        let long = max(image.width, image.height)
        let scale = min(1, maxLongSide / CGFloat(long))
        let outW = Int(CGFloat(image.width) * scale)
        let outH = Int(CGFloat(image.height) * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: outW, pixelsHigh: outH,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: outW, height: outH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [.compressionFactor: 0.8])
    }
}
