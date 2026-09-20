import SwiftUI

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue
    @AppStorage("autoArchiveEnabled") private var autoArchiveEnabled = true
    @AppStorage("floatingBallEnabled") private var floatingBallEnabled = true
    @AppStorage("menuBarBadgeEnabled") private var menuBarBadgeEnabled = true
    @AppStorage("aiProvider") private var aiProviderRaw = AIProviderKind.zhipu.rawValue
    @AppStorage("aiBaseURL") private var aiBaseURL = AIProviderKind.zhipu.defaultBaseURL
    @AppStorage("aiModel") private var aiModel = AIProviderKind.zhipu.defaultModel
    @AppStorage("aiPrompt") private var aiPrompt = AITaskParser.defaultPrompt
    @State private var aiKey = AISettings.apiKey
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false
    @State private var recordingHotkey = false
    @State private var hotkeyMonitor: Any?

    private var provider: AIProviderKind { AIProviderKind(rawValue: aiProviderRaw) ?? .zhipu }
    private var skin: AppSkin { AppSkin.from(skinRaw) }
    private var glass: Bool { skin == .glass }

    var body: some View {
        ZStack {
            if glass {
                VisualEffectBackdrop()
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsCard(icon: "paintpalette.fill", title: "外观") {
                        appearanceSection
                    }
                    SettingsCard(icon: "sparkles", title: "AI 截图解析") {
                        aiSection
                    }
                    SettingsCard(icon: "gearshape.fill", title: "通用") {
                        generalSection
                    }
                    Text("待办 AiTodo v1.4.0 · 数据保存在本机")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(14)
            }
        }
        .frame(minWidth: 400, minHeight: 600)
        .background(glass ? Color.clear : Theme.appBackground)
        .onDisappear { stopHotkeyRecording() }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $skinRaw) {
                ForEach(AppSkin.allCases) { skin in
                    Text(skin.label).tag(skin.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(skin.caption)
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - AI 截图解析

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $aiProviderRaw) {
                ForEach(AIProviderKind.allCases) { kind in
                    Text(kind.label).tag(kind.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: aiProviderRaw) { newValue in
                if let kind = AIProviderKind(rawValue: newValue) {
                    aiBaseURL = kind.defaultBaseURL
                    aiModel = kind.defaultModel
                }
            }

            fieldLabel("API Key（保存在本机钥匙串）")
            SecureField("sk-…", text: $aiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack(spacing: 6) {
                TextField("Base URL", text: $aiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                TextField("模型", text: $aiModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 110)
                Button("默认") {
                    let kind = AIProviderKind(rawValue: aiProviderRaw) ?? .zhipu
                    aiBaseURL = kind.defaultBaseURL
                    aiModel = kind.defaultModel
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
            }

            fieldLabel("识别提示词")
            TextEditor(text: $aiPrompt)
                .font(.system(size: 11))
                .frame(height: 84)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.controlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.chromeBorder)
                )
            HStack {
                Spacer()
                Button("恢复默认提示词") { aiPrompt = AITaskParser.defaultPrompt }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }

            HStack {
                Button("测试连接") { testConnection() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .disabled(testing)
                if testing {
                    ProgressView().scaleEffect(0.5)
                }
                if let testResult {
                    Text(testResult)
                        .font(.system(size: 11))
                        .foregroundColor(testOK ? .green : Theme.overdue)
                        .lineLimit(2)
                }
            }

            Text("隐私：截图仅在你按下快捷键时发送给所配置的 AI 服务商")
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - 通用

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $autoArchiveEnabled) {
                Text("完成后自动归档")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            Text("已完成的任务将在当天结束后（次日）自动移入归档")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)

            Divider()

            HStack {
                Text("截图快捷键")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text(recordingHotkey ? "按下新组合键…" : hotkeyDisplay)
                    .font(.system(size: 12))
                    .foregroundColor(recordingHotkey ? Theme.textSecondary : Theme.textPrimary)
                Button(recordingHotkey ? "取消" : "更改") { toggleHotkeyRecording() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
            Text(hotkeyStatusText)
                .font(.system(size: 10))
                .foregroundColor(ScreenshotManager.shared.hotkeyRegistered ? Theme.textTertiary : Theme.overdue)

            HStack {
                Button("立即截图测试（不经快捷键）") { ScreenshotManager.shared.trigger() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }

            Divider()

            Toggle(isOn: $floatingBallEnabled) {
                Text("桌面悬浮球")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            Text("屏幕上常驻四象限计数悬浮球：左键显示/隐藏待办窗口，可拖动，右键更多操作")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)

            Toggle(isOn: $menuBarBadgeEnabled) {
                Text("菜单栏数字")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            Text("菜单栏常驻四色分格，显示各象限未完成数，点击弹出快捷菜单")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - 小组件

    private var hotkeyStatusText: String {
        let status = ScreenshotManager.shared.hotkeyRegisterStatus
        if ScreenshotManager.shared.hotkeyRegistered {
            return "✅ 系统级快捷键已注册，任意界面按下即触发"
        }
        return "❌ 快捷键注册失败（错误码 \(status)），该组合键可能已被其他软件占用，请更改后重试"
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundColor(Theme.textTertiary)
    }

    // MARK: - 快捷键录制

    private var hotkeyDisplay: String {
        let defaults = UserDefaults.standard
        let mods = defaults.object(forKey: "shotModifiers") as? Int ?? 1572864   // ⌘⌥
        let key = defaults.string(forKey: "shotKeyDisplay") ?? "S"
        var text = ""
        if mods & 1 << 20 != 0 { text += "⌘" }
        if mods & 1 << 19 != 0 { text += "⌥" }
        if mods & 1 << 18 != 0 { text += "⌃" }
        if mods & 1 << 17 != 0 { text += "⇧" }
        return text + key
    }

    private func toggleHotkeyRecording() {
        recordingHotkey ? stopHotkeyRecording() : startHotkeyRecording()
    }

    private func startHotkeyRecording() {
        guard hotkeyMonitor == nil else { return }
        recordingHotkey = true
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc 取消
                stopHotkeyRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // 必须带修饰键，避免记录普通字符
            guard !mods.isEmpty, mods.isSubset(of: [.command, .option, .control, .shift]),
                  let display = event.charactersIgnoringModifiers, !display.isEmpty else {
                return event
            }
            UserDefaults.standard.set(Int(event.keyCode), forKey: "shotKeyCode")
            UserDefaults.standard.set(mods.rawValue, forKey: "shotModifiers")
            UserDefaults.standard.set(display, forKey: "shotKeyDisplay")
            stopHotkeyRecording()
            ScreenshotManager.shared.reapplyHotkey()
            return nil
        }
    }

    private func stopHotkeyRecording() {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
        recordingHotkey = false
    }

    // MARK: - 测试连接

    private func testConnection() {
        AISettings.provider = provider
        AISettings.baseURL = aiBaseURL
        AISettings.model = aiModel
        AISettings.prompt = aiPrompt
        AISettings.apiKey = aiKey
        testing = true
        testResult = nil
        Task {
            do {
                let message = try await AIProvider.testConnection()
                await MainActor.run {
                    testOK = true
                    testResult = message
                    testing = false
                }
            } catch {
                await MainActor.run {
                    testOK = false
                    testResult = error.localizedDescription
                    testing = false
                }
            }
        }
    }
}

/// 设置分区卡片：跟随皮肤的圆角卡片 + 图标标题
struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: Content
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue

    var body: some View {
        let glass = AppSkin.from(skinRaw) == .glass
        let base = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(hex: 0x4CAF7E)))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            base.fill(glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Theme.cardBase))
        )
        .overlay(base.strokeBorder(Theme.cardBorder))
    }
}
