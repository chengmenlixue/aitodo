import SwiftUI

/// AI 识别结果确认面板：逐条修改标题/象限、勾选后批量添加
struct AIResultPanel: View {
    @ObservedObject var manager: ScreenshotManager
    @EnvironmentObject private var store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var focusedRow: UUID?
    @State private var keyMonitor: Any?
    @State private var expandedQuadrantRow: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI 识别结果（\(manager.resultTasks.count)）")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button {
                    manager.dismissResults()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    ForEach(manager.resultTasks.indices, id: \.self) { index in
                        resultRow($manager.resultTasks[index],
                                  opensUpward: index == manager.resultTasks.count - 1)
                    }
                }
            }
            .frame(minHeight: 100, maxHeight: 280)

            HStack {
                Text("光标在标题框时按 ↑/↓ 切换该条象限")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                Spacer()
                Button("取消") { manager.dismissResults() }
                    .keyboardShortcut(.cancelAction)
                Button("添加所选") { addSelected() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 500)
        .onAppear { installQuadrantKeyMonitor() }
        .onDisappear { removeQuadrantKeyMonitor() }
    }

    // MARK: - ↑/↓ 键循环切换聚焦行的象限（与主窗口输入框一致）

    private func installQuadrantKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard focusedRow != nil else { return event }
            switch (event.keyCode, event.charactersIgnoringModifiers) {
            case (125, _), (_, "\u{F701}"):   // ↓
                cycleFocusedQuadrant(+1)
                return nil
            case (126, _), (_, "\u{F702}"):   // ↑
                cycleFocusedQuadrant(-1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeQuadrantKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func cycleFocusedQuadrant(_ offset: Int) {
        guard let id = focusedRow,
              let index = manager.resultTasks.firstIndex(where: { $0.id == id }) else { return }
        let all = Quadrant.allCases
        let current = manager.resultTasks[index].quadrant
        manager.resultTasks[index].quadrant = all[(all.firstIndex(of: current)! + offset + all.count) % all.count]
    }

    /// 可选主任务（未完成、未归档的顶层任务）
    private var parentCandidates: [TaskItem] {
        store.tasks.filter { !$0.isArchived && !$0.isDone }
    }

    private func parentAttachMenu(_ task: Binding<ParsedTask>) -> some View {
        Menu {
            Section("作为子任务添加到") {
                ForEach(parentCandidates) { parent in
                    Button("\(parent.quadrant.title) · \(String(parent.title.prefix(16)))") {
                        task.wrappedValue.parentID = parent.id
                        task.wrappedValue.parentTitle = parent.title
                    }
                    .disabled(parent.id == task.wrappedValue.parentID)
                }
                if task.wrappedValue.parentID != nil {
                    Divider()
                    Button("取消，按象限添加") {
                        task.wrappedValue.parentID = nil
                        task.wrappedValue.parentTitle = nil
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.badge.plus")
                Text(task.wrappedValue.parentTitle.map { "→ \(String($0.prefix(10)))" } ?? "子任务")
            }
            .font(.system(size: 10))
            .foregroundColor(task.wrappedValue.parentID != nil ? task.quadrant.wrappedValue.accent : Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("选择主任务后，该条将作为其子任务添加")
    }

    private func resultRow(_ task: Binding<ParsedTask>, opensUpward: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                task.selected.wrappedValue.toggle()
            } label: {
                Image(systemName: task.selected.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(task.selected.wrappedValue ? task.quadrant.wrappedValue.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(task.selected.wrappedValue ? "不添加" : "添加")

            TextField("任务标题", text: task.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
                .focused($focusedRow, equals: task.id)

            QuadrantPicker(
                quadrant: task.quadrant,
                isExpanded: expandedQuadrantRow == task.wrappedValue.id,
                isDisabled: task.parentID != nil,
                opensUpward: opensUpward,
                toggle: {
                    expandedQuadrantRow = expandedQuadrantRow == task.wrappedValue.id ? nil : task.wrappedValue.id
                },
                pick: { quadrant in
                    task.quadrant.wrappedValue = quadrant
                    expandedQuadrantRow = nil
                }
            )
            parentAttachMenu(task)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.rowBackground)
        )
    }

    private func addSelected() {
        for task in manager.resultTasks where task.selected {
            if let parentID = task.parentID {
                store.addSubtask(id: parentID, title: task.title)
            } else {
                store.add(title: task.title, quadrant: task.quadrant)
            }
        }
        manager.dismissResults()
    }
}

/// 单行的象限选择控件：胶囊标签 + 内联自绘下拉选项
/// 不用 SwiftUI Menu：系统菜单的弹出依赖应用激活态，而识别面板是不激活面板——
/// 应用在后台时点 Menu 毫无响应（用户反馈「类型点不动」）。
/// Button + 自绘选项列表不经过 NSMenu，应用未激活时同样可点可选。
private struct QuadrantPicker: View {
    @Binding var quadrant: Quadrant
    let isExpanded: Bool
    let isDisabled: Bool
    let opensUpward: Bool
    let toggle: () -> Void
    let pick: (Quadrant) -> Void

    @State private var hovering = false

    var body: some View {
        label
            .overlay(alignment: opensUpward ? .top : .bottom) {
                if isExpanded {
                    options.offset(y: opensUpward ? -58 : 58).zIndex(20)
                }
            }
    }

    private var label: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                Circle()
                    .fill(quadrant.accent)
                    .frame(width: 8, height: 8)
                Text(quadrant.title)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.12 : 0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.3 : 1)
        .onHover { hovering = $0 }
        .help(isDisabled ? "已作为子任务，象限跟随主任务" : "点击选择象限")
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Quadrant.allCases) { candidate in
                Button {
                    pick(candidate)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(candidate.accent)
                            .frame(width: 7, height: 7)
                        Text(candidate.title)
                            .font(.system(size: 11))
                            .foregroundColor(candidate == quadrant ? Theme.textPrimary : Theme.textSecondary)
                        Spacer(minLength: 0)
                        if candidate == quadrant {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(candidate.accent)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 136)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.cardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}
