import AppKit
import Combine
import Foundation

/// 拖拽放置语义：排序插入 或 嵌套为子任务
enum DropPlacement {
    case reorderTo(quadrant: Quadrant, index: Int)
    case nestInto(parentID: UUID)
}

final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []

    // 拖拽会话状态：全局共享（跨卡片），beginDrag 时设置，落下时清除
    @Published var draggingID: UUID?
    /// 实时腾位/嵌套的目标行（用于虚线高亮）
    @Published var nestTargetID: UUID?
    private var dragSnapshot: Data?
    /// SwiftUI 拖拽没有「会话结束」回调，靠本地事件监视器兜底清理
    private var dragEndMonitor: Any?

    private let fileURL: URL
    private var cancellables = Set<AnyCancellable>()
    private var archiveTimer: Timer?

    func beginDrag(id: UUID) {
        DebugLog.write("beginDrag: \(id)")
        dragSnapshot = try? JSONEncoder().encode(tasks)
        draggingID = id
        installDragEndWatch()
    }

    /// 拖拽会话结束但未落放（按 Esc 取消、拖出窗口外松手）时，SwiftUI 不会通知：
    /// 下一次本地鼠标按下/按键时清理拖拽状态，避免源行停留在「拖拽中」外观。
    /// 只清状态不回滚内容——保留用户松手前看到的最后一次实时腾位结果。
    private func installDragEndWatch() {
        guard dragEndMonitor == nil else { return }
        dragEndMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            self?.abandonDrag()
            return event
        }
    }

    private func abandonDrag() {
        removeDragEndWatch()
        guard draggingID != nil else { return }
        DebugLog.write("拖拽未落放：清理拖拽状态")
        dragSnapshot = nil
        draggingID = nil
        nestTargetID = nil
    }

    private func removeDragEndWatch() {
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndMonitor = nil
        }
    }

    func endDrag() {
        removeDragEndWatch()
        dragSnapshot = nil
        draggingID = nil
        nestTargetID = nil
    }

    /// 把被拖任务从原位置（顶层或子任务）取出；从子任务取出时提升为普通任务
    private func extractDragged(id: UUID) -> TaskItem? {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            guard !tasks[index].isArchived else { return nil }
            return tasks.remove(at: index)
        }
        guard let parentIndex = tasks.firstIndex(where: { $0.subtasks.contains(where: { $0.id == id }) }),
              let subIndex = tasks[parentIndex].subtasks.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let sub = tasks[parentIndex].subtasks.remove(at: subIndex)
        return TaskItem(id: sub.id, title: sub.title,
                        quadrant: tasks[parentIndex].quadrant, isDone: sub.isDone)
    }

    private func placeTopLevel(_ item: inout TaskItem, quadrant: Quadrant, index: Int) {
        item.quadrant = quadrant
        item.isExpanded = false
        insertTopLevel(item, quadrant: quadrant, index: index)
    }

    /// 顶层插入：锚点按目标象限的展示顺序（未完成在前、各自保持录入顺序）计算，
    /// 插入后把该象限的数组段整体重写为展示顺序，避免「已完成穿插在数组前部」时落点错位。
    /// 跨象限的数组顺序没有展示语义（所有视图都按象限过滤/排序），整体重写是安全的。
    private func insertTopLevel(_ item: TaskItem, quadrant: Quadrant, index: Int) {
        let inQuadrant = tasks.filter { !$0.isArchived && $0.quadrant == quadrant }
        var ordered = inQuadrant.filter { !$0.isDone } + inQuadrant.filter { $0.isDone }
        let clamped = min(max(index, 0), ordered.count)
        ordered.insert(item, at: clamped)
        guard let first = tasks.firstIndex(where: { !$0.isArchived && $0.quadrant == quadrant }) else {
            tasks.append(item)
            return
        }
        tasks.removeAll { !$0.isArchived && $0.quadrant == quadrant }
        tasks.insert(contentsOf: ordered, at: first)
    }

    private func placeNested(_ item: inout TaskItem, parentIndex: Int) {
        item.quadrant = tasks[parentIndex].quadrant
        item.dueDate = nil            // 子任务不保留独立提醒
        item.isExpanded = false
        ReminderCenter.cancel(id: item.id)
        tasks[parentIndex].isExpanded = true
        // 子任务保留 id（便于拖拽提升还原）、标题与完成态
        tasks[parentIndex].subtasks.append(Subtask(id: item.id, title: item.title, isDone: item.isDone))
    }

    /// 拖拽放置：顶层排序，或嵌套为某主任务的子任务（自动展开父任务、随子任务提升）
    func applyDropPlacement(id: UUID, placement: DropPlacement) {
        guard var item = extractDragged(id: id) else { return }
        switch placement {
        case .reorderTo(let quadrant, let index):
            placeTopLevel(&item, quadrant: quadrant, index: index)
        case .nestInto(let parentID):
            if let parentIndex = tasks.firstIndex(where: { $0.id == parentID }),
               !tasks[parentIndex].isArchived, !tasks[parentIndex].isDone,
               item.subtasks.isEmpty {
                placeNested(&item, parentIndex: parentIndex)
            } else {
                // 目标不可嵌套（已完成/带子任务）时退化为追加到其象限末尾
                placeTopLevel(&item, quadrant: item.quadrant, index: Int.max)
            }
        }
    }

    init(directory: URL? = nil, seedOnEmpty: Bool = true) {
        let dir = directory
            ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AiTodo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tasks.json")
        self.seedOnEmpty = seedOnEmpty
        load()
        bindAutosave()
        autoArchiveIfNeeded()
        startArchiveTimer()
    }

    private let seedOnEmpty: Bool

    deinit {
        archiveTimer?.invalidate()
    }

    // MARK: - 派生数据

    private var activeTasks: [TaskItem] { tasks.filter { !$0.isArchived } }

    var remainingCount: Int { activeTasks.filter { !$0.isDone }.count }
    var completedCount: Int { activeTasks.count - remainingCount }
    var totalCount: Int { activeTasks.count }

    /// 各象限未完成数，索引对应 Quadrant.rawValue（悬浮球/菜单栏徽标用）
    var pendingCountsByQuadrant: [Int] {
        var counts = [0, 0, 0, 0]
        for task in tasks where !task.isArchived && !task.isDone {
            counts[task.quadrant.rawValue] += 1
        }
        return counts
    }

    var archivedTasks: [TaskItem] {
        tasks.filter(\.isArchived)
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }
    var archivedCount: Int { tasks.filter(\.isArchived).count }

    /// 某象限的活动任务：未完成在前，各自保持录入顺序
    func tasks(in quadrant: Quadrant) -> [TaskItem] {
        let inQuadrant = tasks.filter { !$0.isArchived && $0.quadrant == quadrant }
        return inQuadrant.filter { !$0.isDone } + inQuadrant.filter { $0.isDone }
    }

    // MARK: - 任务操作

    @discardableResult
    func add(title: String, quadrant: Quadrant, dueDate: Date? = nil) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = TaskItem(title: trimmed, quadrant: quadrant, dueDate: dueDate)
        tasks.append(task)
        if let due = task.dueDate {
            ReminderCenter.schedule(id: task.id, title: task.title, due: due)
        }
        return task
    }

    func toggle(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isDone.toggle()
        tasks[index].completedAt = tasks[index].isDone ? Date() : nil
        if tasks[index].isDone {
            ReminderCenter.cancel(id: id)
        } else if let due = tasks[index].dueDate {
            ReminderCenter.schedule(id: id, title: tasks[index].title, due: due)
        }
    }

    func delete(id: UUID) {
        tasks.removeAll { $0.id == id }
        ReminderCenter.cancel(id: id)
    }

    func move(id: UUID, to quadrant: Quadrant) {
        guard let fromIndex = tasks.firstIndex(where: { $0.id == id }),
              !tasks[fromIndex].isArchived else { return }
        var item = tasks.remove(at: fromIndex)
        item.quadrant = quadrant
        insertTopLevel(item, quadrant: quadrant, index: Int.max)
    }

    /// 展开状态（仅视图记忆，不属于内容修改）
    func setExpanded(id: UUID, to value: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isExpanded = value
    }

    func rename(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].isDone else { return }
        tasks[index].title = trimmed
    }

    func setDue(id: UUID, due: Date?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].isDone else { return }
        tasks[index].dueDate = due
        if tasks[index].isDone || due == nil {
            ReminderCenter.cancel(id: id)
        } else {
            ReminderCenter.schedule(id: id, title: tasks[index].title, due: due!)
        }
    }

    func clearCompleted() {
        for task in tasks where task.isDone && !task.isArchived {
            ReminderCenter.cancel(id: task.id)
        }
        tasks.removeAll { $0.isDone && !$0.isArchived }
    }

    // MARK: - 子任务（父任务完成后锁定，不可修改）

    func addSubtask(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].isDone else { return }
        tasks[index].subtasks.append(Subtask(title: trimmed))
    }

    func toggleSubtask(id: UUID, subtaskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].isDone,
              let subIndex = tasks[index].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        tasks[index].subtasks[subIndex].isDone.toggle()
    }

    func deleteSubtask(id: UUID, subtaskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].isDone else { return }
        tasks[index].subtasks.removeAll { $0.id == subtaskID }
    }

    // MARK: - 归档

    func archive(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].isArchived else { return }
        tasks[index].isArchived = true
        tasks[index].archivedAt = Date()
        ReminderCenter.cancel(id: id)
    }

    /// 恢复到原象限
    func unarchive(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].isArchived else { return }
        tasks[index].isArchived = false
        tasks[index].archivedAt = nil
    }

    func clearArchive() {
        tasks.removeAll { $0.isArchived }
    }

    /// 已完成任务在当天结束后（次日）自动归档；可在设置中关闭
    func autoArchiveIfNeeded() {
        guard UserDefaults.standard.object(forKey: "autoArchiveEnabled") as? Bool ?? true else { return }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        for index in tasks.indices where tasks[index].isDone && !tasks[index].isArchived {
            let reference = tasks[index].completedAt ?? tasks[index].createdAt
            if reference < startOfToday {
                tasks[index].isArchived = true
                tasks[index].archivedAt = Date()
            }
        }
    }

    private func startArchiveTimer() {
        archiveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.autoArchiveIfNeeded()
        }
    }

    // MARK: - Persistence

    private func bindAutosave() {
        $tasks
            .dropFirst()
            // 拖拽悬停期间会反复 remove+insert 出现等值中间态；等值不落盘
            .removeDuplicates()
            .sink { [weak self] value in self?.writeToDisk(value) }
            .store(in: &cancellables)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            seedIfEmpty()
            return
        }
        guard let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) else {
            // 解析失败：先备份损坏文件再重建，避免示例数据直接覆盖历史数据
            let backup = fileURL.deletingPathExtension().appendingPathExtension("json.corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            DebugLog.write("tasks.json 解析失败，已备份到 \(backup.path)")
            seedIfEmpty()
            return
        }
        tasks = decoded
    }

    private func seedIfEmpty() {
        guard seedOnEmpty else { return }
        tasks = Self.seedTasks()
        writeToDisk(tasks)
    }

    private func writeToDisk(_ value: [TaskItem]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 首次启动的示例数据，与设计稿一致
    private static func seedTasks() -> [TaskItem] {
        let calendar = Calendar.current
        var due = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        if due < Date() {
            due = calendar.date(byAdding: .day, value: 1, to: due) ?? due
        }
        var base = Date().addingTimeInterval(-3600)
        func stamped() -> Date {
            base = base.addingTimeInterval(60)
            return base
        }
        return [
            TaskItem(title: "完成季度汇报", quadrant: .urgentImportant, createdAt: stamped()),
            TaskItem(title: "准备设计评审材料", quadrant: .urgentImportant, createdAt: stamped()),
            TaskItem(title: "整理项目资料", quadrant: .importantNotUrgent, createdAt: stamped()),
            TaskItem(title: "客户电话回访", quadrant: .urgentNotImportant, createdAt: stamped(), dueDate: due),
        ]
    }
}
