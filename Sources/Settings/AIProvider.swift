import Foundation

/// 一个 AI Provider 配置。MVP 只支持 OpenAI 兼容协议族；Anthropic / Gemini 留接口。
/// Provider 元数据。apiKey 不再持久化在此结构里——存到 Keychain，
/// 通过 id 关联。Codable 时 apiKey 始终写空字符串以保持兼容。
struct AIProvider: Codable, Identifiable, Equatable, Hashable {
    enum Family: String, Codable, CaseIterable, Identifiable {
        case openaiCompatible
        // case anthropic / gemini  // v0.2
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .openaiCompatible: return L("OpenAI 兼容")
            }
        }
    }

    var id: UUID
    var nickname: String
    var family: Family
    var baseURL: String
    var model: String
    /// 内存中的临时 Key（用于编辑器读写）。持久化时不写到 UserDefaults，
    /// 实际通过 Keychain 存取，由 ProviderStore.commitKey 同步。
    var apiKey: String
    var enabled: Bool

    init(
        id: UUID = UUID(),
        nickname: String,
        family: Family = .openaiCompatible,
        baseURL: String,
        model: String,
        apiKey: String = "",
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

    // 序列化时不带 apiKey，避免落到 UserDefaults
    enum CodingKeys: String, CodingKey {
        case id, nickname, family, baseURL, model, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.nickname = try c.decode(String.self, forKey: .nickname)
        self.family = (try? c.decode(Family.self, forKey: .family)) ?? .openaiCompatible
        self.baseURL = try c.decode(String.self, forKey: .baseURL)
        self.model = try c.decode(String.self, forKey: .model)
        self.enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        self.apiKey = ""  // 解码时不取 key，使用方应从 Keychain 加载
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(nickname, forKey: .nickname)
        try c.encode(family, forKey: .family)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(model, forKey: .model)
        try c.encode(enabled, forKey: .enabled)
    }

    /// 构造对应的 AIService。debugSink 非 nil 时启用 prompts.jsonl 记录。
    /// 优先用内存中的 apiKey；若为空再从 Keychain 取。
    /// responseLanguage 决定 AI 返回 reasoning / reminder / summary 用哪种语言；
    /// SessionManager 在起 session 时按 LocalizationManager 当前值注入。
    func makeService(
        debugSink: AIDebugSink? = nil,
        responseLanguage: String = kDefaultAIResponseLanguage
    ) -> AIService {
        let url = URL(string: baseURL) ?? DemoConfig.baseURL
        let key = apiKey.isEmpty
            ? (KeychainStore.get(for: id.uuidString) ?? "")
            : apiKey
        return OpenAICompatibleService(
            baseURL: url,
            model: model,
            apiKey: key,
            debugSink: debugSink,
            responseLanguage: responseLanguage
        )
    }
}

extension AIProvider {
    /// 首次启动用的默认 provider。Key 在 ProviderStore 初始化时写 Keychain。
    /// DEBUG 用开发者本地 LM Studio；Release 给一个空 placeholder，引导
    /// 用户去 Settings 自填，且不暴露开发期的局域网 IP。
    ///
    /// nickname 用 L(...) 本地化——首启时按当前语言显示"Local LM Studio" / "本地 LM Studio"。
    /// 注意：nickname 之后会被持久化（用户改名或后续 reload 时），所以这里的本地化只影响
    /// **首启那一刻的默认显示**；之后用户在 Settings 里改的名字才是 source of truth。
    #if DEBUG
    static var demoFallback: AIProvider {
        AIProvider(
            nickname: L("本地 LM Studio"),
            baseURL: DemoConfig.baseURL.absoluteString,
            model: DemoConfig.model,
            apiKey: ""  // Key 走 Keychain
        )
    }
    #else
    static var demoFallback: AIProvider {
        AIProvider(
            nickname: L("请先到设置中配置 AI 服务"),
            baseURL: DemoConfig.baseURL.absoluteString,
            model: DemoConfig.model,
            apiKey: ""
        )
    }
    #endif
}
