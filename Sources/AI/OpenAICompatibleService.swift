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

    init(
        baseURL: URL = DemoConfig.baseURL,
        model: String = DemoConfig.model,
        apiKey: String = DemoConfig.apiKey,
        session: URLSession = .shared,
        timeout: TimeInterval = DemoConfig.requestTimeout
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.session = session
        self.timeout = timeout
    }

    // MARK: - AIService

    func analyzeTask(_ promise: String) async throws -> TaskAnalysis {
        let raw = try await chatText(
            system: PromptTemplates.analyzeTaskSystem,
            user: PromptTemplates.analyzeTaskUser(promise: promise),
            temperature: 0.3
        )
        return try Self.decode(TaskAnalysis.self, from: raw)
    }

    func analyzeFrame(_ input: FrameAnalysisInput) async throws -> FrameAnalysis {
        let user = PromptTemplates.analyzeFrameUser(
            promise: input.promise,
            appName: input.appName,
            windowTitles: input.windowTitles
        )
        let raw: String
        if let jpeg = input.screenshotJPEG {
            raw = try await chatVision(
                system: PromptTemplates.analyzeFrameSystem,
                user: user,
                imageJPEG: jpeg,
                temperature: 0.3
            )
        } else {
            raw = try await chatText(
                system: PromptTemplates.analyzeFrameSystem,
                user: user,
                temperature: 0.3
            )
        }
        return try Self.decode(FrameAnalysis.self, from: raw)
    }

    func summarize(_ input: SummaryInput) async throws -> String {
        try await chatText(
            system: PromptTemplates.summarizeSystem,
            user: PromptTemplates.summarizeUser(
                promise: input.promise,
                sessionSeconds: input.sessionSeconds,
                fullySec: input.fullySec,
                wanderingSec: input.wanderingSec,
                distractedSec: input.distractedSec,
                idleSec: input.idleSec,
                distractedNotes: input.distractedNotes
            ),
            temperature: 0.7
        )
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
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
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
                underlying: NSError(domain: "Focus", code: -1),
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
    struct Message: Codable { let content: String }
}
