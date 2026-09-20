import SwiftUI

/// AI 识别结果确认面板：逐条修改标题/象限、勾选后批量添加
struct AIResultPanel: View {
    @ObservedObject var manager: ScreenshotManager
    @EnvironmentObject private var store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var focusedRow: UUID?
    @State private var keyMonitor: Any?

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
                    ForEach($manager.resultTasks) { $task in
                        resultRow($task)
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

    private func resultRow(_ task: Binding<ParsedTask>) -> some View {
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

            Menu {
                ForEach(Quadrant.allCases) { quadrant in
                    Button(quadrant.title) { task.quadrant.wrappedValue = quadrant }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(task.quadrant.wrappedValue.accent)
                        .frame(width: 8, height: 8)
                    Text(task.quadrant.wrappedValue.title)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(task.parentID == nil ? 1 : 0.3)
            .disabled(task.parentID != nil)

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
