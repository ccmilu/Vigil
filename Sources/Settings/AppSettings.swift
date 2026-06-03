import Foundation
import SwiftUI

/// 全局可调参数（截屏阈值 + 调试开关），用 @AppStorage 存。
@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("capture.dhashThreshold") var dhashThreshold: Int = 30
    @AppStorage("capture.maxAIIntervalSec") var maxAIIntervalSec: Int = 30
    @AppStorage("capture.idleThresholdSec") var idleThresholdSec: Int = 60
    @AppStorage("debug.enabled") var debugEnabled: Bool = false

    /// 构造 CaptureConfig（每次起 session 时调）
    func makeCaptureConfig() -> CaptureConfig {
        CaptureConfig(
            tickInterval: 5.0,
            dhashThreshold: dhashThreshold,
            maxAIInterval: TimeInterval(maxAIIntervalSec),
            idleThreshold: TimeInterval(idleThresholdSec)
        )
    }
}
