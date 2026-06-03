import Foundation

// MARK: - Public types

/// 任务理解阶段（PRD 5.5 阶段 1）的输出
struct TaskAnalysis: Codable, Equatable {
    enum TaskType: String, Codable {
        case research, writing, design, development, other
    }
    let taskType: TaskType
    /// promise 已清晰则为 nil；不清晰则一句温和建议
    let suggestion: String?
}

/// 单帧判断阶段（PRD 5.5 阶段 2）的输出。
/// 复用 PersistenceModels 里定义的 FocusLevel。
struct FrameAnalysis: Codable, Equatable {
    let level: FocusLevel
    let reasoning: String
    let reminder: String
}

/// 集中处理 AI 调用错误，UI 可以显示具体原因
enum AIServiceError: LocalizedError {
    case invalidResponse(status: Int, body: String)
    case decodingFailed(underlying: Error, raw: String)
    case noChoice
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let status, let body):
            return "HTTP \(status):\n\(body.prefix(400))"
        case .decodingFailed(let err, let raw):
            return "解析失败：\(err.localizedDescription)\n原文：\(raw.prefix(400))"
        case .noChoice:
            return "AI 返回了空 choices"
        case .network(let err):
            return "网络错误：\(err.localizedDescription)"
        }
    }
}
