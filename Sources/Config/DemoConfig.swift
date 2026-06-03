import Foundation

/// Demo 阶段硬编码的本地 AI 配置。
/// 后续会替换为 SwiftData 持久化 + 设置页可编辑。
enum DemoConfig {
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

    /// API Key 从 LocalConfig 读取（被 .gitignore 屏蔽，不进版本库）。
    /// 若 LocalConfig.swift 不存在，构建会报错，提示你照着模板新建一个。
    static let apiKey = LocalConfig.apiKey

    /// URLSession 软上限。任务级硬超时由 CaptureConfig.aiHardTimeout（设置可调）控制；
    /// 这里保持比硬超时大一点的值即可，主要兜底极端 socket 卡死。
    static let requestTimeout: TimeInterval = 60
}
