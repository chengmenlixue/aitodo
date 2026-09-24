import Foundation
import UserNotifications

/// 到点系统通知。仅打包成 .app 后可用（swift run 直跑时自动降级为仅界面提示）。
enum ReminderCenter {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// AI 智能提醒的固定 identifier：新总结替换上一条，不在通知中心堆积
    static let summaryIdentifier = "aitodo.ai-summary"

    static func schedule(id: UUID, title: String, due: Date) {
        guard isAvailable, due > Date() else { return }
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "待办提醒"
        content.body = title
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(id: UUID) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    /// 立即发送一条 AI 总结通知（固定 identifier，先清已送达的旧条避免堆积）
    static func postSummary(title: String, body: String) {
        guard isAvailable else { return }
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [summaryIdentifier])
        center.add(UNNotificationRequest(identifier: summaryIdentifier, content: content, trigger: nil))
    }

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}
