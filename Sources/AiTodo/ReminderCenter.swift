import Foundation
import UserNotifications

/// 到点系统通知。仅打包成 .app 后可用（swift run 直跑时自动降级为仅界面提示）。
enum ReminderCenter {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

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

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}
