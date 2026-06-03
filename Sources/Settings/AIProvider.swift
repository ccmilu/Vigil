import Foundation

/// 一个 AI Provider 配置。MVP 只支持 OpenAI 兼容协议族；Anthropic / Gemini 留接口。
struct AIProvider: Codable, Identifiable, Equatable, Hashable {
    enum Family: String, Codable, CaseIterable, Identifiable {
        case openaiCompatible
        // case anthropic
        // case gemini
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .openaiCompatible: return "OpenAI 兼容"
            }
        }
    }

    var id: UUID
    var nickname: String
    var family: Family
    var baseURL: String
    var model: String
    var apiKey: String
    var enabled: Bool

    init(
        id: UUID = UUID(),
        nickname: String,
        family: Family = .openaiCompatible,
        baseURL: String,
        model: String,
        apiKey: String,
        enabled: Bool = true
    ) {
        self.id = id
        self.nickname = nickname
        self.family = family
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.enabled = enabled
    }

    /// 构造对应的 AIService。debugSink 非 nil 时启用 prompts.jsonl 记录。
    func makeService(debugSink: AIDebugSink? = nil) -> AIService {
        let url = URL(string: baseURL) ?? DemoConfig.baseURL
        return OpenAICompatibleService(
            baseURL: url,
            model: model,
            apiKey: apiKey,
            debugSink: debugSink
        )
    }
}

extension AIProvider {
    static let demoFallback = AIProvider(
        nickname: "本地 LM Studio",
        baseURL: DemoConfig.baseURL.absoluteString,
        model: DemoConfig.model,
        apiKey: DemoConfig.apiKey
    )
}
