import Foundation

/// 单帧分析的输入。
struct FrameAnalysisInput: Sendable {
    let promise: String
    let appName: String
    let windowTitles: String
    /// JPEG 二进制；如为 nil 表示不带图（仅文本判断）
    let screenshotJPEG: Data?
}

/// 整体复盘的输入。
struct SummaryInput: Sendable {
    let promise: String
    let sessionSeconds: Int
    let fullySec: Int
    let wanderingSec: Int
    let distractedSec: Int
    let idleSec: Int
    let distractedNotes: [String]
}

/// 给所有 AI 厂商实现的统一协议。
protocol AIService: Sendable {
    func analyzeTask(_ promise: String) async throws -> TaskAnalysis
    func analyzeFrame(_ input: FrameAnalysisInput) async throws -> FrameAnalysis
    func summarize(_ input: SummaryInput) async throws -> String
}
