import SwiftUI

/// 弹出面板度量：SwiftUI 布局与 NSPanel 设框共用同一套常量
enum PopupMetrics {
    static let width: CGFloat = 264
    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 42
    static let footerHeight: CGFloat = 52
    static let inputHeight: CGFloat = 46
    static let emptyListHeight: CGFloat = 56
    static let maxVisibleRows = 6
    /// 展开详情：状态/创建/截止三行信息
    static let detailBaseHeight: CGFloat = 70
    /// 展开详情：「子任务 m/n」小标题
    static let detailSubHeaderHeight: CGFloat = 22
    static let subtaskRowHeight: CGFloat = 28
    /// 展开详情：底部「添加子任务」输入行
    static let subtaskInputHeight: CGFloat = 32
    /// 展开详情：自定义截止时间的日期选择器行
    static let customDueHeight: CGFloat = 44

    static func height(itemCount: Int, inputVisible: Bool, detail: CGFloat = 0) -> CGFloat {
        let list = itemCount == 0
            ? emptyListHeight
            : CGFloat(min(itemCount, maxVisibleRows)) * rowHeight
        return headerHeight + list + detail + footerHeight + (inputVisible ? inputHeight : 0)
    }

    static func detailHeight(subtaskCount: Int) -> CGFloat {
        let header: CGFloat = subtaskCount == 0 ? 0 : detailSubHeaderHeight
        return detailBaseHeight + header + CGFloat(subtaskCount) * subtaskRowHeight + subtaskInputHeight
    }
}

/// 悬浮球色格弹出的待办面板：该象限未完成列表 + 截图识别 / 快速输入两个快捷按钮
/// 行交互：圆圈勾选完成；点行展开详情（任务信息 + 子任务）；悬停浮现 编辑/时间/归档/删除
struct FloatingBallPopupView: View {
    @ObservedObject var manager: FloatingBallManager
    @ObservedObject var store: TaskStore
    let quadrant: Quadrant

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var pending: [TaskItem] {
        store.tasks(in: quadrant).filter { !$0.isDone }
    }

    /// 列表区高度：与 manager.popupHeight 的算法保持一致（展开详情且不滚动时追加详情高度）
    private var listFrameHeight: CGFloat {
        if pending.isEmpty { return PopupMetrics.emptyListHeight }
        var height = CGFloat(min(pending.count, PopupMetrics.maxVisibleRows)) * PopupMetrics.rowHeight
        if pending.count <= PopupMetrics.maxVisibleRows,
           let expanded = pending.first(where: { $0.id == manager.expandedTaskID }) {
            height += PopupMetrics.detailHeight(subtaskCount: expanded.subtasks.count)
            if manager.customDueTaskID == expanded.id {
                height += PopupMetrics.customDueHeight
            }
        }
        return height
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: PopupMetrics.headerHeight)
                .overlay(alignment: .bottom) { divider }
            listGroup
                .frame(height: listFrameHeight)
            if manager.popupInputVisible {
                inputRow
                    .frame(height: PopupMetrics.inputHeight)
                    .overlay(alignment: .top) { divider }
                    .transition(.opacity)
            }
            footer
                .frame(height: PopupMetrics.footerHeight)
                .overlay(alignment: .top) { divider }
        }
        .frame(width: PopupMetrics.width)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
        )
        .animation(.easeInOut(duration: 0.18), value: manager.popupInputVisible)
        .onChange(of: manager.popupQuadrant) { _ in draft = "" }
        .onChange(of: manager.popupInputVisible) { visible in
            guard visible else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { inputFocused = true }
        }
    }

    // MARK: - 分区

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: quadrant.accentHex))
                .frame(width: 10, height: 10)
            Text(quadrant.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Text("\(pending.count) 项")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var listGroup: some View {
        if pending.isEmpty {
            ZStack {
                Text("暂无待办")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(pending) { task in
                        TaskLine(
                            task: task,
                            accent: Color(hex: quadrant.accentHex),
                            isExpanded: manager.expandedTaskID == task.id,
                            isCustomDue: manager.customDueTaskID == task.id,
                            onToggleDone: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    store.toggle(id: task.id)
                                }
                            },
                            onToggleExpand: { manager.setExpandedTask(task.id) },
                            onRename: { store.rename(id: task.id, to: $0) },
                            onSetDue: { store.setDue(id: task.id, due: $0) },
                            onArchive: { store.archive(id: task.id) },
                            onDelete: { store.delete(id: task.id) },
                            onToggleSubtask: { store.toggleSubtask(id: task.id, subtaskID: $0) },
                            onAddSubtask: { store.addSubtask(id: task.id, title: $0) },
                            onToggleCustomDue: { manager.toggleCustomDue(task.id) },
                            onEditBegin: { manager.activatePopupForEditing() }
                        )
                        .frame(height: rowHeight(of: task))
                        if task.id != pending.last?.id {
                            Rectangle()
                                .fill(Theme.chipBackground)
                                .frame(height: 0.5)
                                .padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    /// 行高：42 + 展开详情（详情随面板展开时不产生滚动，直接占位）
    private func rowHeight(of task: TaskItem) -> CGFloat {
        var height = PopupMetrics.rowHeight
        if manager.expandedTaskID == task.id,
           pending.count <= PopupMetrics.maxVisibleRows {
            height += PopupMetrics.detailHeight(subtaskCount: task.subtasks.count)
            if manager.customDueTaskID == task.id {
                height += PopupMetrics.customDueHeight
            }
        }
        return height
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: quadrant.accentHex))
            TextField("添加到「\(quadrant.title)」…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
                .focused($inputFocused)
                .onSubmit { addDraft() }
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: addDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: quadrant.accentHex))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            quickButton(icon: "camera.viewfinder", title: "截图识别", active: false) {
                manager.triggerScreenshotFromPopup()
            }
            quickButton(icon: "square.and.pencil", title: "快速输入", active: manager.popupInputVisible) {
                manager.togglePopupInput()
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.chipBackground)
            .frame(height: 0.5)
    }

    // MARK: - 动作

    private func addDraft() {
        // 与主窗口输入一致：支持「18:30 买菜」快速带上提醒时间
        let parsed = DueParser.parse(draft)
        guard !parsed.title.isEmpty else { return }
        if store.add(title: parsed.title, quadrant: quadrant, dueDate: parsed.due) != nil {
            draft = ""
            inputFocused = true
        }
    }

    private func quickButton(icon: String, title: String, active: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(active ? Color(hex: quadrant.accentHex) : Theme.textSecondary)
            .padding(.init(top: 6, leading: 10, bottom: 6, trailing: 10))
            .background(
                Capsule().fill(active ? Color(hex: quadrant.accentHex).opacity(0.16) : Theme.controlBackground)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 任务行

/// 面板任务行：
/// - 圆圈 = 勾选完成；点行 = 展开/收起详情（任务信息 + 子任务 + 添加子任务）
/// - 悬停浮现 编辑 / 时间 / 归档 / 删除 四个小图标
private struct TaskLine: View {
    let task: TaskItem
    let accent: Color
    let isExpanded: Bool
    let isCustomDue: Bool
    let onToggleDone: () -> Void
    let onToggleExpand: () -> Void
    let onRename: (String) -> Void
    let onSetDue: (Date?) -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onToggleSubtask: (UUID) -> Void
    let onAddSubtask: (String) -> Void
    let onToggleCustomDue: () -> Void
    let onEditBegin: () -> Void

    @State private var hovered = false
    @State private var editing = false
    @State private var editDraft = ""
    @State private var subDraft = ""
    @FocusState private var editFocused: Bool
    @FocusState private var subFocused: Bool

    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            line
            if isExpanded {
                detail
            }
        }
    }

    // MARK: 行

    private var line: some View {
        HStack(spacing: 10) {
            circleButton
            if editing {
                editField
            } else {
                titleButton
                if hovered {
                    hoverIcons
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(hovered || isExpanded ? Theme.chipBackground : Color.clear)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.14), value: hovered)
        .onHover { hovered = $0 }
    }

    private var circleButton: some View {
        Button(action: onToggleDone) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.checkBoxRing, lineWidth: 1.5)
                    .background(Circle().fill(accent.opacity(hovered ? 0.22 : 0.001)))
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var titleButton: some View {
        Button(action: onToggleExpand) {
            Text(task.title)
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var editField: some View {
        TextField("编辑任务", text: $editDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(Theme.textPrimary)
            .focused($editFocused)
            .onSubmit { commitEdit() }
            .onChange(of: editFocused) { focused in
                if !focused { commitEdit() }   // 失焦即提交
            }
    }

    /// 悬停小图标：编辑 / 时间 / 归档 / 删除
    private var hoverIcons: some View {
        HStack(spacing: 4) {
            iconButton("pencil", tint: Theme.textTertiary) { beginEdit() }
            dueMenu
            iconButton("archivebox", tint: Theme.textTertiary, action: onArchive)
            iconButton("trash", tint: Theme.overdue.opacity(0.85), action: onDelete)
        }
    }

    private func iconButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 截止时间快捷菜单：相对时间 / 整点日期 / 自定义 / 清除
    private var dueMenu: some View {
        Menu {
            Button("10分钟后") { onSetDue(Date().addingTimeInterval(600)) }
            Button("半小时后") { onSetDue(Date().addingTimeInterval(1800)) }
            Button("1小时后") { onSetDue(Date().addingTimeInterval(3600)) }
            Divider()
            ForEach(Self.dayPresets, id: \.label) { preset in
                Button(preset.label) { onSetDue(preset.date()) }
            }
            Divider()
            Button(isCustomDue ? "收起自定义" : "自定义…") { onToggleCustomDue() }
            Button("清除截止时间") {
                onSetDue(nil)
                if isCustomDue { onToggleCustomDue() }
            }
        } label: {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private static let dayPresets: [(label: String, date: () -> Date)] = {
        let calendar = Calendar.current
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> () -> Date {
            return {
                calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))
                    .map { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: $0) ?? $0 }
                    ?? Date()
            }
        }
        func nextMonday(_ hour: Int) -> () -> Date {
            return {
                let today = calendar.startOfDay(for: Date())
                // 下一个周一（至少 +1 天）：weekday 1=周日 … 7=周六
                let offset = (8 - calendar.component(.weekday, from: today)) % 7 + 1
                return calendar.date(byAdding: .day, value: offset, to: today)
                    .map { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0) ?? $0 }
                    ?? Date()
            }
        }
        return [
            ("今天 18:00", at(0, 18)),
            ("明天 09:00", at(1, 9)),
            ("3 天后 09:00", at(3, 9)),
            ("下周一 09:00", nextMonday(9)),
        ]
    }()

    private func beginEdit() {
        editDraft = task.title
        editing = true
        onEditBegin()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { editFocused = true }
    }

    private func commitEdit() {
        defer { editing = false }
        guard editing else { return }
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != task.title {
            onRename(trimmed)
        }
    }

    // MARK: 展开详情

    private var doneSubtaskCount: Int {
        task.subtasks.filter(\.isDone).count
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 3) {
            infoRow(icon: "circle.dashed", label: "状态",
                    value: task.isDone ? "已完成" : "待完成", valueTint: nil)
            infoRow(icon: "clock",
                    label: "创建",
                    value: Self.dueFormatter.string(from: task.createdAt),
                    valueTint: nil)
            dueInfoRow
            if !task.subtasks.isEmpty {
                subtaskHeader
                ForEach(task.subtasks) { sub in
                    subtaskRow(sub)
                }
            }
            subtaskInputRow
            if isCustomDue {
                customDueRow
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 添加子任务：回车即加，输入时自动激活键盘
    private var subtaskInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(accent)
            TextField("添加子任务…", text: $subDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Theme.textPrimary)
                .focused($subFocused)
                .onSubmit { addSub() }
                .onChange(of: subFocused) { focused in
                    if focused { onEditBegin() }
                }
            if !subDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: addSub) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: PopupMetrics.subtaskInputHeight)
    }

    private func addSub() {
        let title = subDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onAddSubtask(title)
        subDraft = ""
        subFocused = true
    }

    /// 自定义截止时间：内嵌日期选择器，滚动即保存
    private var customDueRow: some View {
        DatePicker(
            "截止",
            selection: Binding(
                get: { task.dueDate ?? Date() },
                set: { onSetDue($0) }
            ),
            displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .font(.system(size: 11))
        .frame(height: PopupMetrics.customDueHeight)
    }

    private var dueInfoRow: some View {
        let overdue = task.dueDate.map { $0 < Date() } ?? false
        return infoRow(icon: "calendar",
                       label: "截止",
                       value: task.dueDate.map { Self.dueFormatter.string(from: $0) } ?? "未设置",
                       valueTint: overdue ? Theme.overdue : nil)
    }

    private func infoRow(icon: String, label: String, value: String, valueTint: Color?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 10))
                .foregroundColor(valueTint ?? Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(height: 15)
    }

    private var subtaskHeader: some View {
        Text("子任务 \(doneSubtaskCount)/\(task.subtasks.count)")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Theme.textTertiary)
            .frame(height: PopupMetrics.detailSubHeaderHeight - 6, alignment: .bottom)
    }

    private func subtaskRow(_ sub: Subtask) -> some View {
        Button(action: { onToggleSubtask(sub.id) }) {
            HStack(spacing: 8) {
                ZStack {
                    if sub.isDone {
                        Circle()
                            .fill(accent.opacity(0.9))
                        Image(systemName: "checkmark")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .strokeBorder(Theme.checkBoxRing, lineWidth: 1.2)
                    }
                }
                .frame(width: 13, height: 13)
                Text(sub.title)
                    .font(.system(size: 11))
                    .strikethrough(sub.isDone)
                    .foregroundColor(sub.isDone ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: PopupMetrics.subtaskRowHeight)
    }
}
