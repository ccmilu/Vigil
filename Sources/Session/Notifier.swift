import Foundation
import UserNotifications
import OSLog

/// 系统通知封装。首次启动会请求权限。
enum Notifier {
    private static let logger = Logger(subsystem: "com.jason12138.focus", category: "Notifier")

    /// App 启动时调一次
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.warning("通知授权失败：\(error.localizedDescription)")
        }
    }

    static func notifyDistraction(reminder: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Focus · 拉你回来一下"
        content.body = reminder.isEmpty ? "似乎偏离了承诺，看看回到正事？" : reminder
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(req)
        } catch {
            logger.error("通知发送失败：\(error.localizedDescription)")
        }
    }
}
