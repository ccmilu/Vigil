import Foundation

/// 默认 AI 配置。
///
/// DEBUG 用开发者本地的 LM Studio（含 LAN IP），方便日常开发跑通；
/// Release **不带任何实环境信息**——baseURL 是占位 localhost、model / apiKey
/// 留空，避免开发期的局域网 IP 与个人 API key 随 .dmg 发出去。
///
/// 后续会替换为 SwiftData 持久化 + 设置页可编辑。
enum DemoConfig {
    #if DEBUG
    /// LM Studio 局域网地址（OpenAI 兼容）
    static let baseURL = URL(string: "http://192.168.1.23:1234/v1")!

    /// LM Studio 中加载的模型 ID（仅作记录；LM Studio 实际不校验此字段，
    /// 服务端始终用当前加载的模型响应）。
    /// 在 LM Studio 的 Developer 面板可看到当前加载的模型 ID。
    ///
    /// 注意：本 App 会向模型发送截图（多模态），所以加载的模型必须支持视觉。
    /// 例如 qwen2.5-vl-7b-instruct / qwen2-vl-7b / llava 等；
    /// 纯文本模型（如 Qwen3-4B）会忽略图片或报错。
    static let model = "qwen2.5-vl-7b-instruct"

    /// API Key 默认留空。LM Studio / Ollama 默认不校验此字段；若你的服务端开了
    /// "API Key Required"，在 App 内「设置」里填一次即可（持久化到 Keychain）。
    static let apiKey = ""
    #else
    /// Release：占位符 URL，用户首启会看到默认 provider 但 URL/model/key 均
    /// 是空白或 localhost，需自己去 Settings 配置后才能跑。
    static let baseURL = URL(string: "http://localhost:1234/v1")!
    static let model = ""
    static let apiKey = ""
    #endif

    /// URLSession 软上限。任务级硬超时由 CaptureConfig.aiHardTimeout（设置可调）控制；
    /// 这里保持比硬超时大一点的值即可，主要兜底极端 socket 卡死。
    static let requestTimeout: TimeInterval = 60
}
