import Foundation

/// Demo 阶段硬编码的本地 AI 配置。
/// 后续会替换为 SwiftData 持久化 + 设置页可编辑。
enum DemoConfig {
    /// LM Studio 局域网地址（OpenAI 兼容）
    static let baseURL = URL(string: "http://192.168.1.23:1234/v1")!

    /// LM Studio 中加载的模型 ID（在 LM Studio 的 Developer 面板复制）
    /// 如果你装的不是这个模型，改成实际的 ID
    static let model = "qwen2.5-vl-7b-instruct"

    /// LM Studio 默认不校验 Key，但 OpenAI 协议要求字段存在
    static let apiKey = "lm-studio"

    /// 单次请求超时（秒）
    static let requestTimeout: TimeInterval = 30
}
