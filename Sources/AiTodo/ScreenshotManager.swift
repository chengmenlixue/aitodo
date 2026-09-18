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
        guard let data = imageData else { return }
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

final class SelectionCoordinator {
    private var windows: [NSWindow] = []

    func begin(onComplete: @escaping (Data?) -> Void) {
        close()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: .borderless,
                                  backing: .buffered,
                                  defer: false,
                                  screen: screen)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = false

            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onComplete = { [weak self] viewRect in
                let displayID = screen.displayID
                // 关键：覆盖窗铺满该显示器，选区坐标即显示器本地坐标（顶部原点）。
                // 不能叠加 screen.frame.minX 等全局偏移，否则拓展屏选区越界导致截图失败。
                let bounds = CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height)
                let sourceRect = bounds.intersection(viewRect)
                let pixelScale = screen.backingScaleFactor
                self?.close()
                Task { @MainActor in
                    do {
                        let image = try await CaptureDisplay.image(displayID: displayID,
                                                                   sourceRect: sourceRect,
                                                                   pixelScale: pixelScale)
                        let data = CaptureImageTool.png(from: image, maxLongSide: 1600)
                        onComplete(data)
                    } catch {
                        DebugLog.write("截图失败：\(error.localizedDescription)")
                        onComplete(nil)
                    }
                }
            }
            view.onCancel = { [weak self] in
                self?.close()
                onComplete(nil)
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            windows.append(window)
        }
    }

    func close() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

}

// MARK: - 屏幕截图（ScreenCaptureKit）

enum CaptureDisplay {
    static func image(displayID: CGDirectDisplayID, sourceRect: CGRect, pixelScale: CGFloat) async throws -> CGImage {
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
}

// MARK: - 选区覆盖视图

final class SelectionOverlayView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: () -> Void = {}

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }   // 顶部原点，截图换算更直观

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
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
