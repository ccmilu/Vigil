import Foundation

/// 给所有 AI 厂商实现的统一协议。MVP 只需要 analyzeTask；
/// analyzeFrame / summarize 在后续接入截屏后启用。
protocol AIService: Sendable {
    func analyzeTask(_ promise: String) async throws -> TaskAnalysis
    // func analyzeFrame(_ input: FrameInput) async throws -> FrameAnalysis
    // func summarize(_ input: SummaryInput) async throws -> String
}
