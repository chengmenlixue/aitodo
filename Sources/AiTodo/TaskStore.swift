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

    private let fileURL: URL
    private var cancellables = Set<AnyCancellable>()
    private var archiveTimer: Timer?

    func beginDrag(id: UUID) {
        DebugLog.write("beginDrag: \(id)")
        dragSnapshot = try? JSONEncoder().encode(tasks)
        draggingID = id
    }

    /// 拖拽取消（移出卡片未落下）：恢复拖拽开始时的快照
    func cancelDrag() {
        if let data = dragSnapshot,
           let restored = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = restored
        }
        endDrag()
    }

    func endDrag() {
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
        let targetIDs = tasks.filter { !$0.isArchived && $0.quadrant == quadrant }.map(\.id)
        let clamped = min(max(index, 0), targetIDs.count)
        if clamped < targetIDs.count,
           let anchorIndex = tasks.firstIndex(where: { $0.id == targetIDs[clamped] }) {
            tasks.insert(item, at: anchorIndex)
        } else if let lastIndex = targetIDs.last,
                  let tailIndex = tasks.firstIndex(where: { $0.id == lastIndex }) {
            tasks.insert(item, at: tailIndex + 1)
        } else {
            tasks.append(item)
        }
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
        move(id: id, to: quadrant, insertionIndex: nil)
    }

    /// 展开状态（仅视图记忆，不属于内容修改）
    func setExpanded(id: UUID, to value: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isExpanded = value
    }

    /// 拖拽排序 / 跨象限移动：insertionIndex 为目标象限展示列表中的插入位置（nil = 追加到末尾）
    func move(id: UUID, to quadrant: Quadrant, insertionIndex: Int?) {
        guard let fromIndex = tasks.firstIndex(where: { $0.id == id }),
              !tasks[fromIndex].isArchived else { return }
        var item = tasks.remove(at: fromIndex)
        item.quadrant = quadrant

        let targetIDs = tasks.filter { !$0.isArchived && $0.quadrant == quadrant }.map(\.id)
        let index = min(max(insertionIndex ?? targetIDs.count, 0), targetIDs.count)
        if index < targetIDs.count,
           let anchorIndex = tasks.firstIndex(where: { $0.id == targetIDs[index] }) {
            tasks.insert(item, at: anchorIndex)
        } else if let lastIndex = targetIDs.last,
                  let tailIndex = tasks.firstIndex(where: { $0.id == lastIndex }) {
            tasks.insert(item, at: tailIndex + 1)
        } else {
            tasks.append(item)
        }
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
            .sink { [weak self] value in self?.writeToDisk(value) }
            .store(in: &cancellables)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) else {
            if seedOnEmpty {
                tasks = Self.seedTasks()
                writeToDisk(tasks)
            }
            return
        }
        tasks = decoded
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
