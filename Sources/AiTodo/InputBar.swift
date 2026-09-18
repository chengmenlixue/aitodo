import SwiftUI

struct InputBar: View {
    @Binding var text: String
    @Binding var selectedQuadrant: Quadrant
    var onSubmit: () -> Void

    @FocusState private var focused: Bool
    @State private var keyMonitor: Any?
    private let shortcuts: [KeyEquivalent] = ["1", "2", "3", "4"]

    var body: some View {
        HStack(spacing: 12) {
            TextField("记一件小事，回车添加...", text: $text, prompt: prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(selectedQuadrant.accent)
                .animation(Motion.micro, value: selectedQuadrant)
                .focused($focused)
                .defaultFocus($focused, true)
                .onSubmit(submit)
                .onExitCommand { text = "" }

            Spacer(minLength: 12)

            HStack(spacing: 15) {
                ForEach(Quadrant.allCases) { quadrant in
                    quadrantDot(quadrant, shortcut: shortcuts[quadrant.rawValue])
                }
            }
            .animation(Motion.pop, value: selectedQuadrant)

            addButton
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 66)
        .frame(maxWidth: .infinity)
        .background(ChromeBackground(cornerRadius: 18))
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private var prompt: Text {
        Text("记一件小事，回车添加...").foregroundColor(Theme.textTertiary)
    }

    // MARK: - ↑/↓ 键循环选择颜色

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 仅在输入框聚焦且事件来自主窗口时拦截，避免影响弹窗/行内编辑的上下键
            guard focused,
                  event.window === NSApp.mainWindow,
                  let characters = event.charactersIgnoringModifiers else { return event }
            switch (event.keyCode, characters) {
            case (125, _), (_, "\u{F701}"):  // ↓ 下一个颜色
                stepQuadrant(+1)
                return nil
            case (126, _), (_, "\u{F702}"):  // ↑ 上一个颜色
                stepQuadrant(-1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func stepQuadrant(_ offset: Int) {
        let all = Quadrant.allCases
        let index = (all.firstIndex(of: selectedQuadrant)! + offset + all.count) % all.count
        selectedQuadrant = all[index]
    }

    private func quadrantDot(_ quadrant: Quadrant, shortcut: KeyEquivalent) -> some View {
        Button {
            selectedQuadrant = quadrant
        } label: {
            Circle()
                .fill(quadrant.accent)
                .frame(width: 15, height: 15)
                .overlay(alignment: .center) {
                    if selectedQuadrant == quadrant {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.4)
                            .frame(width: 25, height: 25)
                            // GSAP back.out：选中环弹跳出现
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .help("\(quadrant.title)（⌘\(quadrant.rawValue + 1)）")
    }

    private var addButton: some View {
        Button {
            submit()
            focused = true
        } label: {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.actionButton)
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Theme.actionForeground)
                )
        }
        .buttonStyle(.plain)
        .help("添加任务，支持 “18:30 买菜” 快速带上提醒时间")
    }

    private func submit() {
        onSubmit()
    }
}
