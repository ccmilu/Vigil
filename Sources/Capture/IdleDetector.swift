import Foundation
import CoreGraphics

/// 用 CGEventSource 查询系统输入空闲时长（秒）。
enum IdleDetector {
    static func secondsSinceLastInput() -> TimeInterval {
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: ~0)!)
    }
}
