import SwiftUI
import UniformTypeIdentifiers

struct TaskRow: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue
    let task: TaskItem
    /// 正在被拖拽的源行：半透明 + 虚线幽灵描边（变形为落位槽）
    var isDragSource: Bool = false
    var onDragStarted: () -> Void = {}
    var dropHandlers: RowDropHandlers? = nil

    @State private var hovered = false
    @State private var isEditing = false
    @State private var editDraft = ""
    @State private var showsDuePopover = false
    @State private var dueDraft = Date()
    @FocusState private var editFocused: Bool

    private var skin: AppSkin { AppSkin.from(skinRaw) }
    private var accent: Color { task.quadrant.accent }
    private var isOverdue: Bool {
        guard let due = task.dueDate, !task.isDone else { return false }
        return due < Date()
    }

    var body: some View {
        HStack(spacing: 12) {
            checkBox

            if isEditing {
                TextField("", text: $editDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($editFocused)
                    .onSubmit(commitEdit)
                    .onExitCommand { isEditing = false }
            } else {
                Text(task.title)
                    .font(.system(size: 14))
                    .foregroundColor(task.isDone ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(task.isDone, color: Theme.textTertiary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { beginEdit() }
            }

            Spacer(minLength: 8)

            trailingControls
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .opacity(isDragSource ? 1 : 0)
        )
        .scaleEffect(isDragSource ? 0.98 : 1)
        .opacity(isDragSource ? 0.55 : 1)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : Motion.softIn, value: isDragSource)
        .animation(reduceMotion ? nil : Motion.micro, value: hovered)
        .animation(reduceMotion ? nil : Motion.pop, value: task.isDone)
        .onHover { hovered = $0 }
        .onDrag {
            DebugLog.write("onDrag 触发：\(task.title)")
            let provider = NSItemProvider(object: task.id.uuidString as NSString)
            DispatchQueue.main.async { onDragStarted() }
            return provider
        }
        .contextMenu { contextItems }
        .onDrop(of: [UTType.plainText], delegate: RowDropDelegate(
            onEnter: dropHandlers?.onEnter ?? {},
            onExit: dropHandlers?.onExit ?? {},
            onDrop: dropHandlers?.onDrop ?? {}))
        .popover(isPresented: $showsDuePopover) { duePopover }
    }

    // MARK: - Subviews

    private var checkBox: some View {
        Button {
            store.toggle(id: task.id)
        } label: {
            ZStack {
                if task.isDone {
                    Circle().fill(accent)
                        .transition(.scale(scale: 0.5))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Circle().strokeBorder(Theme.checkBoxRing, lineWidth: 1.6)
                        .transition(.opacity)
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var trailingControls: some View {
        if let due = task.dueDate {
            Button {
                dueDraft = due
                showsDuePopover = true
            } label: {
                chipLabel(DueChipText.text(for: due))
            }
            .buttonStyle(.plain)
            .help("修改提醒时间")

            if hovered {
                HStack(spacing: 6) {
                    archiveButton
                    deleteButton
                }
                // GSAP：微交互从尾侧缩放淡入（back.out 手感）
                .transition(.scale(scale: 0.8, anchor: .trailing).combined(with: .opacity))
            }
        } else if hovered {
            HStack(spacing: 6) {
                clockButton
                archiveButton
                deleteButton
            }
            .transition(.scale(scale: 0.8, anchor: .trailing).combined(with: .opacity))
        }
    }

    private func chipLabel(_ text: String) -> some View {
        DueChip(text: text, isOverdue: isOverdue)
    }

    private var clockButton: some View {
        Button {
            dueDraft = defaultDraft
            showsDuePopover = true
        } label: {
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.controlCircle))
        }
        .buttonStyle(.plain)
        .help("设置提醒时间")
    }

    private var archiveButton: some View {
        Button {
            store.archive(id: task.id)
        } label: {
            Image(systemName: "archivebox")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.controlCircle))
        }
        .buttonStyle(.plain)
        .help("归档（或次日自动归档）")
    }

    private var deleteButton: some View {
        Button {
            store.delete(id: task.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.controlCircle))
        }
        .buttonStyle(.plain)
        .help("删除任务")
    }

    private var duePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("提醒时间")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            DatePicker("", selection: $dueDraft, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            HStack {
                Spacer()
                if task.dueDate != nil {
                    Button("清除提醒", role: .destructive) {
                        store.setDue(id: task.id, due: nil)
                        showsDuePopover = false
                    }
                }
                Button("保存") {
                    store.setDue(id: task.id, due: dueDraft)
                    showsDuePopover = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder private var contextItems: some View {
        Menu("移动到") {
            ForEach(Quadrant.allCases) { quadrant in
                Button(quadrant.title) { store.move(id: task.id, to: quadrant) }
            }
        }
        Divider()
        Button(task.isDone ? "标记为未完成" : "标记为完成") { store.toggle(id: task.id) }
        Button("设置提醒时间…") {
            dueDraft = task.dueDate ?? defaultDraft
            showsDuePopover = true
        }
        Button("归档") { store.archive(id: task.id) }
        Divider()
        Button("删除", role: .destructive) { store.delete(id: task.id) }
    }

    private var rowBackground: some View {
        let glass = skin == .glass
        let base = RoundedRectangle(cornerRadius: 14, style: .continuous)
        // 任务颜色从前往后（左→右）渐变淡出到行背景色
        let wash = LinearGradient(
            stops: [
                .init(color: accent.opacity(task.isDone ? 0.24 : 0.48), location: 0),
                .init(color: accent.opacity(task.isDone ? 0.08 : 0.16), location: 0.55),
                .init(color: accent.opacity(0), location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        return Group {
            if glass {
                base.fill(.thinMaterial).overlay(base.fill(wash))
            } else {
                base.fill(Theme.rowBackground).overlay(base.fill(wash))
            }
        }
    }

    // MARK: - Actions

    private var defaultDraft: Date {
        Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    }

    private func beginEdit() {
        editDraft = task.title
        isEditing = true
        DispatchQueue.main.async { editFocused = true }
    }

    private func commitEdit() {
        store.rename(id: task.id, to: editDraft)
        isEditing = false
    }
}
