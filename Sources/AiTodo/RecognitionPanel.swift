import AppKit
import Combine
import SwiftUI

/// 截图识别结果浮动面板：独立于主窗口，悬浮在任意应用之上展示
/// - phase == .results → AI 识别结果确认面板；.failed → 错误卡片；其余隐藏
final class RecognitionPanelController: NSObject {
    static let shared = RecognitionPanelController()

    private var panel: RecognitionPanel?
    private var store: TaskStore?
    private var subscription: AnyCancellable?

    func start(store: TaskStore) {
        guard self.store == nil else { return }
        self.store = store
        subscription = ScreenshotManager.shared.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                switch phase {
                case .results, .failed:
                    self?.showPanel()
                case .idle, .recognizing:
                    self?.panel?.orderOut(nil)
                }
            }
    }

    private func ensurePanel() -> RecognitionPanel {
        if let panel { return panel }
        let panel = RecognitionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        guard let store else { return panel }
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = RecognitionPanelView(manager: ScreenshotManager.shared, store: store)
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
        return panel
    }

    private func showPanel() {
        let panel = ensurePanel()
        panel.orderFrontRegardless()
        // 按内容自适应尺寸（结果行数/错误文案不同）
        if let hosting = panel.contentView as? NSHostingView<RecognitionPanelView> {
            let visible = NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = hosting.fittingSize
            let width = min(max(size.width, 380), visible.width - 40)
            let height = min(max(size.height, 220), visible.height - 60)
            panel.setFrame(NSRect(x: visible.midX - width / 2,
                                  y: visible.midY - height / 2,
                                  width: width, height: height),
                            display: true)
        }
        // 识别结果的标题输入需要键盘：激活应用但不呼出主窗口
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }
}

/// 识别结果面板：可成 key（标题编辑/快捷键），不激活式面板 + 背景可拖动
final class RecognitionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 面板内容：按 phase 切换结果确认 / 失败卡片
struct RecognitionPanelView: View {
    @ObservedObject var manager: ScreenshotManager
    let store: TaskStore

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 4)
            switch manager.phase {
            case .results:
                AIResultPanel(manager: manager)
                    .environmentObject(store)
            case .failed:
                errorCard
            default:
                EmptyView()
            }
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.overdue)
                Text("截图识别失败")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button {
                    manager.dismissError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Text(manager.lastError ?? "")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("知道了") { manager.dismissError() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
