import Foundation

/// OpenAI 兼容协议的实现，覆盖 OpenAI、Kimi、DeepSeek、SiliconFlow、
/// 火山 Doubao、OpenRouter、LM Studio、Ollama 等。
///
/// 关键点：
/// - URLSession 可注入，便于单元测试 mock；
/// - 对 LM Studio / Ollama 做兼容（去除 `detail` 字段、容忍非严格 JSON）；
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
        let raw = try await chat(
            system: PromptTemplates.analyzeTaskSystem,
            user: PromptTemplates.analyzeTaskUser(promise: promise),
            temperature: 0.3
        )
        return try Self.decodeTaskAnalysis(raw)
    }

    // MARK: - Internal

    /// 发起一次 chat completion，返回 message.content 字符串。
    func chat(system: String, user: String, temperature: Double) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ],
            temperature: temperature
        )
        request.httpBody = try JSONEncoder().encode(payload)

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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.invalidResponse(status: http.statusCode, body: body)
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

    /// 把 AI 返回的字符串解析成 TaskAnalysis。容忍模型把 JSON 包在 markdown 里。
    static func decodeTaskAnalysis(_ raw: String) throws -> TaskAnalysis {
        let json = extractFirstJSONObject(from: raw) ?? raw
        guard let data = json.data(using: .utf8) else {
            throw AIServiceError.decodingFailed(
                underlying: NSError(domain: "Focus", code: -1),
                raw: raw
            )
        }
        do {
            return try JSONDecoder().decode(TaskAnalysis.self, from: data)
        } catch {
            throw AIServiceError.decodingFailed(underlying: error, raw: raw)
        }
    }

    /// 从可能含 markdown 标记的字符串中抽出第一个 {...} JSON 块。
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

private struct ChatRequest: Codable {
    let model: String
    let messages: [Message]
    let temperature: Double

    struct Message: Codable {
        let role: String
        let content: String
    }
}

private struct ChatResponse: Codable {
    let choices: [Choice]
    struct Choice: Codable {
        let message: Message
    }
    struct Message: Codable {
        let content: String
    }
}
