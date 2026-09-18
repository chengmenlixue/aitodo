import SwiftUI

/// AI 识别结果确认面板：逐条修改标题/象限、勾选后批量添加
struct AIResultPanel: View {
    @ObservedObject var manager: ScreenshotManager
    @EnvironmentObject private var store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                Spacer()
                Button("取消") { manager.dismissResults() }
                    .keyboardShortcut(.cancelAction)
                Button("添加所选") { addSelected() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 500)
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
            store.add(title: task.title, quadrant: task.quadrant)
        }
        manager.dismissResults()
    }
}
