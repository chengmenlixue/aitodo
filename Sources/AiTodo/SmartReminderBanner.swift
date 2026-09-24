import AppKit
import SwiftUI

/// 应用内通知横幅：系统横幅时长固定约 5 秒且不可调、图标受双副本签名影响可能空白，
/// 因此 AI 总结改用自绘浮动面板展示——时长可控（默认 20 秒）、自带 App 图标、点击打开主窗口。
final class SmartReminderBannerController {
    static let shared = SmartReminderBannerController()
    private init() {}

    /// 横幅停留时长
    static let displayDuration: TimeInterval = 20

    private var panel: SmartReminderBannerPanel?
    private var hideTask: Task<Void, Never>?

    /// 顶部右侧弹出横幅；重复调用会先撤掉上一条并重置计时
    func show(title: String, message: String, stats: String?) {
        dismiss()
        guard let screen = NSScreen.main else { return }

        let view = SmartReminderBannerView(title: title, message: message, stats: stats) { [weak self] in
            self?.dismiss()
            FloatingBallManager.shared.restoreMainWindow()
        }
        let panel = SmartReminderBannerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let contentView = NSHostingView(rootView: view)
        panel.contentView = contentView

        let size = contentView.fittingSize
        panel.setContentSize(size)
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 12,
            y: visible.maxY - size.height - 10
        ))
        DebugLog.write("横幅显示：size=\(size) frame=\(panel.frame) screen=\(screen.localizedName) visible=\(visible)")

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.displayDuration * 1_000_000_000))
            await MainActor.run { self?.dismiss() }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            },
            completionHandler: { panel.orderOut(nil) }
        )
    }
}

/// 非激活面板：横幅出现时不抢应用焦点，点击由内容层处理
final class SmartReminderBannerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct SmartReminderBannerView: View {
    let title: String
    let message: String
    let stats: String?
    let onOpen: () -> Void

    // 横幅悬浮在任意亮暗内容上，且要不受皮肤（纯白/深色）影响，
    // 固定用高对比深底浅字，不取 Theme（会随皮肤翻转为白底暗字或中灰正文）
    private let bannerBackground = Color(hex: 0x1B1B1F)
    private let bannerTitle = Color(hex: 0xFFFFFF)
    private let bannerBody = Color(hex: 0xF0F0F2)
    private let bannerMeta = Color(hex: 0xB8B9BF)
    private let bannerBullet = Color(hex: 0x8E9096)

    /// 横幅里的一行：段落或列表项
    private struct BannerRow: Identifiable {
        let id: Int
        let isBullet: Bool
        let content: AttributedString
    }

    /// Markdown 拆行：行内语法（加粗/斜体/代码）交给 AttributedString 原生渲染，
    /// 块级列表 Text 不支持，改为自绘圆点；解析失败的行退化为纯文本
    private var rows: [BannerRow] {
        var result: [BannerRow] = []
        for rawLine in message.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var isBullet = false
            var text = line
            for prefix in ["- ", "• ", "* "] where line.hasPrefix(prefix) {
                isBullet = true
                text = String(line.dropFirst(prefix.count))
                break
            }
            // 有序列表（"1. "）同样按项目符渲染
            if let first = text.first, first.isNumber,
               text.dropFirst().hasPrefix(". ") {
                isBullet = true
                text = String(text.dropFirst(2))
            }
            // 行内语法（加粗/斜体/代码）由系统 markdown 解析嵌入渲染意图；
            // 简版 init 即可（逐行拆分后无块级语法，interpretedSyntax 参数在捆绑工具链上不可用）
            let attributed = (try? AttributedString(markdown: text)) ?? AttributedString(text)
            result.append(BannerRow(id: result.count, isBullet: isBullet, content: attributed))
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .cornerRadius(9)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(bannerTitle)
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 7) {
                        if row.isBullet {
                            Circle()
                                .fill(bannerBullet)
                                .frame(width: 4, height: 4)
                                .padding(.top, 8)
                        }
                        Text(row.content)
                            .font(.system(size: 13))
                            .foregroundColor(bannerBody)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let stats, !stats.isEmpty {
                    Text(stats)
                        .font(.system(size: 12))
                        .foregroundColor(bannerMeta)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(bannerBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onOpen() }
    }
}
