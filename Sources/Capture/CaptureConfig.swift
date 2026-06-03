import Foundation

/// 截屏决策的可调参数。先内部硬编码；v0.2 把它放进 Settings。
struct CaptureConfig: Sendable {
    /// 基础 tick（秒）
    var tickInterval: TimeInterval = 5.0
    /// dHash 汉明距离阈值（256-bit）。≥ 此距离视为"画面有变化"
    var dhashThreshold: Int = 30
    /// 兜底强制调 AI 的最大间隔（秒）
    var maxAIInterval: TimeInterval = 30.0
    /// 用户输入空闲多久算 idle
    var idleThreshold: TimeInterval = 60.0
    /// AI 调用超时
    var aiTimeout: TimeInterval = 30.0

    static let `default` = CaptureConfig()
}

/// FrameAnalyzer 的决策结果，用于诊断和测试断言。
enum FrameDecision: Equatable, Sendable {
    case skippedIdle(seconds: TimeInterval)
    case skippedNoWindows
    case skippedAIBusy
    case skippedDhashStable(distance: Int)
    case analyzed(reason: AnalysisReason, distance: Int?, level: FocusLevel, fromAI: Bool)

    enum AnalysisReason: String, Sendable {
        case firstFrame
        case dhashChanged
        case timeFallback
    }
}
