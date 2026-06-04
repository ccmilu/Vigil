import Foundation
import SwiftUI

/// 全局可调参数（截屏阈值 + 调试开关），用 @AppStorage 存。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("capture.dhashThreshold") var dhashThreshold: Int = 30
    @AppStorage("capture.maxAIIntervalSec") var maxAIIntervalSec: Int = 30
    @AppStorage("capture.idleThresholdSec") var idleThresholdSec: Int = 60
    @AppStorage("capture.aiHardTimeoutSec") var aiHardTimeoutSec: Int = 30
    @AppStorage("debug.enabled") var debugEnabled: Bool = false

    // MARK: 三种提醒（distract / idle / wandering）
    /// distract 跳变后第一次必弹；之后是否每隔 N 秒持续提醒（用户没回来）
    @AppStorage("alert.distract.intervalEnabled") var distractIntervalEnabled: Bool = true
    /// distract 间歇提醒的秒数（从遮罩关闭瞬间起算）
    @AppStorage("alert.distract.intervalSec") var distractIntervalSec: Int = 30

    /// 持续 idle（不在电脑前 / 玩手机）多久才发提醒
    @AppStorage("alert.idle.enabled") var idleAlertEnabled: Bool = true
    /// idle 持续多少秒触发首次提醒（在 idleThresholdSec 标 idle 后再等这么久）
    @AppStorage("alert.idle.thresholdSec") var idleAlertThresholdSec: Int = 120
    /// idle 状态继续期间，每隔多少秒重弹声音（用户不看屏幕，靠声音召回）
    @AppStorage("alert.idle.repeatSec") var idleAlertRepeatSec: Int = 30

    /// 持续 wandering（边缘走神）多久弹一次轻提醒（不像 distract 那么强烈）
    @AppStorage("alert.wandering.enabled") var wanderingAlertEnabled: Bool = true
    /// wandering 持续多少秒触发提醒
    @AppStorage("alert.wandering.thresholdSec") var wanderingAlertThresholdSec: Int = 120

    /// 构造 CaptureConfig（每次起 session 时调）
    func makeCaptureConfig() -> CaptureConfig {
        CaptureConfig(
            tickInterval: 5.0,
            dhashThreshold: dhashThreshold,
            maxAIInterval: TimeInterval(maxAIIntervalSec),
            idleThreshold: TimeInterval(idleThresholdSec),
            aiHardTimeout: TimeInterval(aiHardTimeoutSec)
        )
    }
}
