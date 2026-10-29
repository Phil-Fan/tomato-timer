import Foundation
import UserNotifications

enum NotificationScheduler {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// 在 App 处于后台、锁屏或睡眠时也能收到提醒。
    static func schedule(in seconds: TimeInterval, title: String, body: String, id: String) {
        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // App 自己会播放提示音，通知保持安静，避免两边同时响。
        content.sound = nil

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func cancel(id: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
