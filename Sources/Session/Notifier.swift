import Foundation
import UserNotifications
import OSLog

/// 系统通知封装。首次启动会请求权限。
///
/// macOS 上 App 处于前台时，系统默认**不显示**通知。
/// 通过 `ForegroundNotificationDelegate` 让前台也以 banner+sound 形式呈现。
enum Notifier {
    private static let logger = Logger(subsystem: "com.jason12138.focus", category: "Notifier")
    nonisolated(unsafe) private static let delegate = ForegroundNotificationDelegate()

    /// App 启动时调一次
    static func setUp() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
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
        content.interruptionLevel = .timeSensitive
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

/// 让 App 前台时通知也以 banner 显示。
private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
