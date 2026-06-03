import Foundation

/// 接收每次 AI 调用的原始 prompt / 响应，写到 session 目录下的 prompts.jsonl。
/// 仅在 Settings → Debug → "记录完整 prompt" 打开时启用。
struct AIDebugRecord: Sendable, Codable {
    let ts: String
    let stage: String       // analyzeTask / analyzeFrame / summarize
    let systemPrompt: String
    let userPrompt: String
    let hasImage: Bool
    let responseRaw: String
    let latencyMs: Int
    let error: String?
}

actor AIDebugSink {
    private let url: URL
    private let iso = ISO8601DateFormatter()

    init(url: URL) {
        self.url = url
    }

    func write(_ rec: AIDebugRecord) {
        guard let data = try? JSONEncoder().encode(rec) else { return }
        guard var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            do {
                _ = try h.seekToEnd()
                try h.write(contentsOf: Data(line.utf8))
                try h.close()
            } catch { /* 忽略 */ }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func record(
        stage: String,
        systemPrompt: String,
        userPrompt: String,
        hasImage: Bool,
        responseRaw: String,
        latencyMs: Int,
        error: String? = nil
    ) {
        let rec = AIDebugRecord(
            ts: iso.string(from: .now),
            stage: stage,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            hasImage: hasImage,
            responseRaw: responseRaw,
            latencyMs: latencyMs,
            error: error
        )
        write(rec)
    }
}
