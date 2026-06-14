import Foundation

/// OpenAI 兼容协议的实现，覆盖 OpenAI、Kimi、DeepSeek、SiliconFlow、
/// 火山 Doubao、OpenRouter、LM Studio、Ollama 等。
///
/// 关键点：
/// - URLSession 可注入，便于单元测试 mock；
/// - 视觉请求支持本地 host 自动剥离 `detail` 字段（Ollama / LM Studio 兼容）；
/// - JSON 解析失败时尝试 regex 兜底提取 `{...}`，避免提示词包裹 markdown 时崩盘。
struct OpenAICompatibleService: AIService {
    let baseURL: URL
    let model: String
    let apiKey: String
    let session: URLSession
    let timeout: TimeInterval
    let debugSink: AIDebugSink?
    /// analyzeTask（用 String 入参，没机会经 input struct 传 language）的回复语言。
    /// SessionManager 在构造 service 时按用户当前语言注入；
    /// 默认值兜测试与历史调用路径。
    let responseLanguage: String

    init(
        baseURL: URL = DemoConfig.baseURL,
        model: String = DemoConfig.model,
        apiKey: String = DemoConfig.apiKey,
        session: URLSession = .shared,
        timeout: TimeInterval = DemoConfig.requestTimeout,
        debugSink: AIDebugSink? = nil,
        responseLanguage: String = kDefaultAIResponseLanguage
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.session = session
        self.timeout = timeout
        self.debugSink = debugSink
        self.responseLanguage = responseLanguage
    }

    // MARK: - AIService

    func analyzeTask(_ promise: String) async throws -> TaskAnalysis {
        let system = PromptTemplates.analyzeTaskSystem(responseLanguage: responseLanguage)
        let user = PromptTemplates.analyzeTaskUser(promise: promise)
        let raw = try await loggedChat(
            stage: "analyzeTask",
            system: system, user: user, hasImage: false
        ) { try await chatText(system: system, user: user, temperature: 0.3) }
        return try Self.decode(TaskAnalysis.self, from: raw)
    }

    func analyzeFrame(_ input: FrameAnalysisInput) async throws -> FrameAnalysis {
        let system = PromptTemplates.analyzeFrameSystem(responseLanguage: input.responseLanguage)
        let user = PromptTemplates.analyzeFrameUser(
            promise: input.promise,
            appName: input.appName,
            windowTitles: input.windowTitles
        )
        let raw = try await loggedChat(
            stage: "analyzeFrame",
            system: system, user: user, hasImage: input.screenshotJPEG != nil
        ) {
            if let jpeg = input.screenshotJPEG {
                return try await chatVision(system: system, user: user, imageJPEG: jpeg, temperature: 0.3)
            } else {
                return try await chatText(system: system, user: user, temperature: 0.3)
            }
        }
        return try Self.decode(FrameAnalysis.self, from: raw)
    }

    func summarize(_ input: SummaryInput) async throws -> String {
        let system = PromptTemplates.summarizeSystem(responseLanguage: input.responseLanguage)
        let user = PromptTemplates.summarizeUser(
            promise: input.promise,
            sessionSeconds: input.sessionSeconds,
            fullySec: input.fullySec,
            wanderingSec: input.wanderingSec,
            distractedSec: input.distractedSec,
            idleSec: input.idleSec,
            distractedNotes: input.distractedNotes
        )
        return try await loggedChat(
            stage: "summarize",
            system: system, user: user, hasImage: false
        ) { try await chatText(system: system, user: user, temperature: 0.7) }
    }

    // MARK: - 视觉能力探测（Settings 里用）

    /// 给一张图，要求模型描述图中内容；用于人工验证"模型确实能看到图"。
    /// 经过 loggedChat 包装，debug sink 可记录此次调用（stage = "describeImage"）。
    func describeImage(_ jpeg: Data) async throws -> String {
        let system = """
            You will be shown ONE image. Describe in ONE concise Simplified Chinese sentence \
            what specific content (windows, text, app, colors, layout) you can see in the image. \
            If you receive no image or the image is blank, reply EXACTLY: 我没有看到图片。
            """
        let user = "Describe what you see."
        return try await loggedChat(
            stage: "describeImage",
            system: system,
            user: user,
            hasImage: true
        ) {
            try await chatVision(system: system, user: user, imageJPEG: jpeg, temperature: 0.2)
        }
    }

    // MARK: - debug wrapper

    private func loggedChat(
        stage: String,
        system: String, user: String, hasImage: Bool,
        run: () async throws -> String
    ) async throws -> String {
        let start = Date()
        do {
            let raw = try await run()
            if let sink = debugSink {
                let latency = Int(Date().timeIntervalSince(start) * 1000)
                await sink.record(
                    stage: stage, systemPrompt: system, userPrompt: user,
                    hasImage: hasImage, responseRaw: raw, latencyMs: latency
                )
            }
            return raw
        } catch {
            if let sink = debugSink {
                let latency = Int(Date().timeIntervalSince(start) * 1000)
                await sink.record(
                    stage: stage, systemPrompt: system, userPrompt: user,
                    hasImage: hasImage, responseRaw: "", latencyMs: latency,
                    error: error.localizedDescription
                )
            }
            throw error
        }
    }

    // MARK: - Internal: 纯文本 chat

    func chatText(system: String, user: String, temperature: Double) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": temperature
        ]
        return try await sendChat(body: body)
    }

    // MARK: - Internal: 视觉 chat（含图片）

    func chatVision(
        system: String,
        user: String,
        imageJPEG: Data,
        temperature: Double
    ) async throws -> String {
        let base64 = imageJPEG.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(base64)"

        var imageDict: [String: Any] = ["url": dataURL]
        if !isLocalHost {
            imageDict["detail"] = "low"  // 本地服务（LM Studio/Ollama）不识别此字段
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": [
                    ["type": "text", "text": user],
                    ["type": "image_url", "image_url": imageDict]
                ]]
            ],
            "temperature": temperature
        ]
        return try await sendChat(body: body)
    }

    // MARK: - Internal: HTTP & 解析

    private func sendChat(body: [String: Any]) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIServiceError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse(status: -1, body: "non-http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.invalidResponse(status: http.statusCode, body: bodyStr)
        }
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw AIServiceError.decodingFailed(
                underlying: error,
                raw: String(data: data, encoding: .utf8) ?? ""
            )
        }
        // decoded.choices.first?.message.content 的类型是 String??（外层来自 choices.first?，
        // 内层来自 content: String?）。?? nil 将双层 Optional 压缩为单层，再 guard let 展开。
        guard let content = decoded.choices.first?.message.content ?? nil, !content.isEmpty else {
            throw AIServiceError.noChoice
        }
        return content
    }

    private var isLocalHost: Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" { return true }
        if host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("10.") { return true }
        if host.hasSuffix(".local") { return true }
        return false
    }

    // MARK: - Static helpers (test 可访问)

    static func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let json = extractFirstJSONObject(from: raw) ?? raw
        guard let data = json.data(using: .utf8) else {
            throw AIServiceError.decodingFailed(
                underlying: NSError(domain: "Vigil", code: -1),
                raw: raw
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIServiceError.decodingFailed(underlying: error, raw: raw)
        }
    }

    /// 兼容旧测试入口
    static func decodeTaskAnalysis(_ raw: String) throws -> TaskAnalysis {
        try decode(TaskAnalysis.self, from: raw)
    }

    static func extractFirstJSONObject(from text: String) -> String? {
        var depth = 0
        var start: String.Index?
        for idx in text.indices {
            let ch = text[idx]
            if ch == "{" {
                if depth == 0 { start = idx }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let s = start {
                    return String(text[s...idx])
                }
            }
        }
        return nil
    }
}

// MARK: - Wire types

private struct ChatResponse: Codable {
    let choices: [Choice]
    struct Choice: Codable { let message: Message }
    /// content 声明为 Optional：部分兼容 provider（Kimi、DeepSeek 安全过滤场景）
    /// 会返回 {"content": null} 或完全省略 content 字段。
    /// 两种情况都在 sendChat 里统一抛 AIServiceError.noChoice，
    /// 而不是让 JSONDecoder typeMismatch 导致 decodingFailed 误导用户。
    struct Message: Codable { let content: String? }
}
