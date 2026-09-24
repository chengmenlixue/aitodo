import Foundation
import UserNotifications

/// AI 智能提醒：开启后定时把未完成任务交给 AI 总结，并以系统通知横幅提醒用户。
/// 由 30s tick 的常驻 Timer 驱动（仿 TaskStore.archiveTimer）：
/// 休眠错过的时间点在唤醒后的下一次 tick 补发；应用退出则不再触发。
final class SmartReminderCenter {
    static let shared = SmartReminderCenter()
    private init() {}

    static let summaryTitle = "AI 待办总结"
    /// 清单过长时截断，避免提示词无限膨胀
    private static let maxLines = 50

    private weak var store: TaskStore?
    private var tickTimer: Timer?
    /// 防重入：AI 请求进行中不再叠加触发
    private var isFiring = false

    // MARK: - 设置存取（调度器无视图上下文，直接读写 UserDefaults，与设置页 @AppStorage 同 key）

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "smartReminderEnabled") }

    /// true = 每日定时模式；false/缺省 = 固定间隔模式
    static var isDailyMode: Bool { UserDefaults.standard.string(forKey: "smartReminderMode") == "daily" }

    static var intervalMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: "smartReminderIntervalMinutes")
        return [15, 30, 60, 120, 240].contains(value) ? value : 120
    }

    static var dailyHour: Int {
        let value = UserDefaults.standard.integer(forKey: "smartReminderDailyHour")
        return (0...23).contains(value) ? value : 9
    }

    static var dailyMinute: Int {
        let value = UserDefaults.standard.integer(forKey: "smartReminderDailyMinute")
        return (0...59).contains(value) ? value : 0
    }

    private var lastFireAt: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: "smartReminderLastFireAt")
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "smartReminderLastFireAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "smartReminderLastFireAt")
            }
        }
    }

    /// 设置页「最近结果」状态行（@AppStorage 读同一 key，落盘即刷新）
    private static func record(result: String) {
        UserDefaults.standard.set(result, forKey: "smartReminderLastResult")
    }

    // MARK: - 生命周期

    /// 应用启动时接入任务库并开始调度（RootView.onAppear 调用，仿 FloatingBallManager）
    func start(store: TaskStore) {
        self.store = store
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        DebugLog.write("智能提醒调度器已启动：enabled=\(Self.isEnabled) mode=\(Self.isDailyMode ? "daily" : "interval")")
    }

    /// 设置变化后由设置页调用：立即重估是否到期（新开启时让首条总结马上可见）
    func settingsChanged() {
        tick()
    }

    // MARK: - 调度

    private func tick() {
        guard Self.isEnabled, !isFiring, let store, isDue() else { return }
        fire(store: store)
    }

    /// 当前配置下是否已到期（tick 每 30s 询问一次）
    private func isDue() -> Bool {
        if Self.isDailyMode {
            guard let slot = Calendar.current.date(
                bySettingHour: Self.dailyHour, minute: Self.dailyMinute, second: 0, of: Date()) else { return false }
            // 今天的时间点已过且今天尚未触发 → 到期（含休眠唤醒后的补发）
            return Date() >= slot && (lastFireAt.map { $0 < slot } ?? true)
        }
        // 首次开启（无上次触发时间）立即到期
        guard let last = lastFireAt else { return true }
        return Date() >= last.addingTimeInterval(TimeInterval(Self.intervalMinutes) * 60)
    }

    private func fire(store: TaskStore) {
        isFiring = true
        lastFireAt = Date()
        let pending = Self.pendingTasks(in: store)
        DebugLog.write("智能提醒定时触发：未完成 \(pending.count) 项")
        Task { [weak self] in
            _ = await Self.performSummary(pending: pending)
            await MainActor.run { self?.isFiring = false }
        }
    }

    /// 设置页「立即总结一次」：绕过开关与到期判断，返回给状态行展示的结果文案
    func summarizeNowManually() async -> String {
        guard let store else { return "❌ 应用尚未就绪，请稍后重试" }
        guard !isFiring else { return "⏳ 上一轮总结仍在进行中" }
        isFiring = true
        lastFireAt = Date()
        let pending = Self.pendingTasks(in: store)
        DebugLog.write("智能提醒手动触发：未完成 \(pending.count) 项")
        let message = await Self.performSummary(pending: pending)
        isFiring = false
        return message
    }

    /// 未完成任务 = 未归档且未完成（TaskStore.activeTasks 是 private，这里用公开的 tasks 等价过滤）
    private static func pendingTasks(in store: TaskStore) -> [TaskItem] {
        store.tasks.filter { !$0.isArchived && !$0.isDone }
    }

    /// 执行一次总结并提醒；无任务走本地文案（不调 AI），失败静默只记结果。
    /// 只用应用内横幅展示（不发系统通知）：时长可控、带图标、可手动关闭
    private static func performSummary(pending: [TaskItem]) async -> String {
        do {
            let body: String
            let suffix = statsSuffix(for: pending)
            if pending.isEmpty {
                body = "当前没有未完成的待办，清单很清爽，安排点重要的事或休息一下吧"
            } else {
                // 外层超时兜底 Keychain 授权阻塞（如锁屏期间触发提醒，授权弹窗无法应答会永久挂起）
                let lines = taskLines(pending)
                body = try await AITaskParser.withRequestTimeout(seconds: 45) {
                    try await AITaskParser.summarizeTasks(lines)
                }
            }
            await MainActor.run {
                SmartReminderBannerController.shared.show(title: summaryTitle, message: body, stats: suffix.isEmpty ? nil : suffix)
                record(result: "✅ 成功 · \(timeFormatter.string(from: Date()))")
            }
            DebugLog.write("智能提醒完成：已显示提醒横幅（\(pending.count) 项）")
            return "✅ 已显示提醒横幅"
        } catch {
            DebugLog.write("智能提醒失败：\(error.localizedDescription)")
            await MainActor.run {
                record(result: "❌ 失败 · \(error.localizedDescription)")
            }
            return "❌ \(error.localizedDescription)"
        }
    }

    // MARK: - 提示词组装

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    /// 通知末尾的本地统计后缀（无需 AI 就能算出的硬事实）
    private static func statsSuffix(for pending: [TaskItem]) -> String {
        guard !pending.isEmpty else { return "" }
        let now = Date()
        let overdue = pending.filter { ($0.dueDate ?? .distantFuture) < now }.count
        var text = "共 \(pending.count) 项未完成"
        if overdue > 0 {
            text += " · \(overdue) 项已到期"
        }
        return text
    }

    /// 未完成任务清单 → 提示词行：标题 + 象限 + 截止/逾期情况
    private static func taskLines(_ tasks: [TaskItem]) -> [String] {
        let now = Date()
        let shown = tasks.prefix(maxLines)
        var lines = shown.map { task -> String in
            var line = "- \(task.title)（\(task.quadrant.title)"
            if let due = task.dueDate {
                if due < now {
                    let hours = max(Int(now.timeIntervalSince(due) / 3600), 1)
                    line += hours >= 24 ? "，已逾期 \(hours / 24) 天" : "，已逾期 \(hours) 小时"
                } else if due < now.addingTimeInterval(86_400) {
                    line += "，24 小时内到期"
                } else {
                    line += "，截止 \(timeFormatter.string(from: due))"
                }
            }
            return line + "）"
        }
        if tasks.count > shown.count {
            lines.append("（另有 \(tasks.count - shown.count) 项未列出）")
        }
        return lines
    }
}
