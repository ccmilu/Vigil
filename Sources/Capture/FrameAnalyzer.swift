import Foundation
import CoreGraphics
import OSLog

/// 5 闸门决策流，每 tickInterval 跑一次：
///
/// 1. idle（用户长时间无输入）→ 标 idle，不调 AI
/// 2. 截屏失败 / 桌面 only / 无窗口 → skip
/// 3. AI 仍在跑 → skip 这一帧
/// 4. dHash 距离 < 阈值 且 距上次 AI 不到 maxAIInterval → skip
/// 5. 否则调 AI 分析这一帧
///
/// 同时把每一帧的诊断（含 dHash / 距离 / 决策原因）写到本地 jsonl，用于日后调参。
actor FrameAnalyzer {

    private let service: AIService
    private let capture: ScreenCaptureManager
    private let config: CaptureConfig
    private let sessionID: UUID
    private let diagnosticLogURL: URL

    private var lastAnalyzedHash: Data?
    private var lastAnalyzedAt: Date?
    private var lastLevel: FocusLevel?
    private var isAIBusy = false

    private let logger = Logger(subsystem: "com.jason12138.focus", category: "FrameAnalyzer")
    private let isoFormatter = ISO8601DateFormatter()

    /// 上层喂入的会话上下文（promise + 是否暂停等），用 actor 内部状态隔离。
    private var currentPromise: String

    init(
        service: AIService,
        capture: ScreenCaptureManager = ScreenCaptureManager(),
        config: CaptureConfig = .default,
        sessionID: UUID,
        promise: String,
        diagnosticLogURL: URL
    ) {
        self.service = service
        self.capture = capture
        self.config = config
        self.sessionID = sessionID
        self.currentPromise = promise
        self.diagnosticLogURL = diagnosticLogURL
    }

    func setPromise(_ p: String) { currentPromise = p }

    // MARK: - 主入口：一帧

    /// 调用一次决策流，返回这帧的决策与可能的 AnalysisRecord 字段。
    /// `now` 注入便于测试。`captureOverride` 让测试可以不依赖真截屏。
    func tick(
        now: Date = .now,
        captureOverride: ((@Sendable () async throws -> CGImage)?) = nil
    ) async -> FrameTickResult {
        // Gate 1: idle
        let idleSec = MainActorBridge.runSync { IdleDetector.secondsSinceLastInput() }
        if idleSec >= config.idleThreshold {
            return await record(.skippedIdle(seconds: idleSec), at: now)
        }

        // Gate 2: AI 排队
        if isAIBusy {
            return await record(.skippedAIBusy, at: now)
        }

        // Gate 3: 截屏（含 desktop-only / no-windows 判定）
        let image: CGImage
        do {
            if let override = captureOverride {
                image = try await override()
            } else {
                image = try await capture.captureMainDisplay()
            }
        } catch ScreenCaptureManager.CaptureError.desktopOnly,
                ScreenCaptureManager.CaptureError.noDisplay {
            return await record(.skippedNoWindows, at: now)
        } catch {
            logger.error("截屏失败：\(error.localizedDescription)")
            return await record(.skippedNoWindows, at: now)
        }

        // Gate 4: dHash 变化检测 + 时间兜底
        let hash = DHashComputer.hash(image)
        var distance: Int? = nil
        var reason: FrameDecision.AnalysisReason
        if let prev = lastAnalyzedHash {
            let d = DHashComputer.distance(prev, hash)
            distance = d
            let timedOut = lastAnalyzedAt.map { now.timeIntervalSince($0) >= config.maxAIInterval } ?? true
            if d < config.dhashThreshold && !timedOut {
                return await record(.skippedDhashStable(distance: d), at: now, image: image, hash: hash)
            }
            reason = timedOut ? .timeFallback : .dhashChanged
        } else {
            reason = .firstFrame
        }

        // Gate 5: 调 AI
        let front = MainActorBridge.runSync { FrontAppDetector.detect() }
        isAIBusy = true
        defer { isAIBusy = false }

        let start = Date()
        let jpeg: Data
        do {
            jpeg = try await encodeJPEG(image)
        } catch {
            logger.error("JPEG 编码失败：\(error.localizedDescription)")
            return await record(
                .analyzed(reason: reason, distance: distance, level: lastLevel ?? .wandering, fromAI: false),
                at: now, image: image, hash: hash
            )
        }
        do {
            let result = try await service.analyzeFrame(
                FrameAnalysisInput(
                    promise: currentPromise,
                    appName: front.appName,
                    windowTitles: front.windowTitles,
                    screenshotJPEG: jpeg
                )
            )
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            let hasChanged = lastLevel != nil && lastLevel != result.level
            lastAnalyzedHash = hash
            lastAnalyzedAt = now
            lastLevel = result.level
            return await record(
                .analyzed(reason: reason, distance: distance, level: result.level, fromAI: true),
                at: now, image: image, hash: hash,
                front: front, ai: result, latencyMs: latency, hasChanged: hasChanged
            )
        } catch {
            logger.error("AI 分析失败：\(error.localizedDescription)")
            // AI 失败：复用上次 level（如果有），fromAI=false
            let level = lastLevel ?? .wandering
            lastAnalyzedHash = hash
            lastAnalyzedAt = now
            return await record(
                .analyzed(reason: reason, distance: distance, level: level, fromAI: false),
                at: now, image: image, hash: hash, front: front
            )
        }
    }

    // MARK: - 记录器

    private func record(
        _ decision: FrameDecision,
        at now: Date,
        image: CGImage? = nil,
        hash: Data? = nil,
        front: FrontAppDetector.Result? = nil,
        ai: FrameAnalysis? = nil,
        latencyMs: Int = 0,
        hasChanged: Bool = false
    ) async -> FrameTickResult {
        // 写诊断日志
        let entry: [String: Any] = [
            "ts": isoFormatter.string(from: now),
            "sessionID": sessionID.uuidString,
            "decision": decisionName(decision),
            "distance": (hash != nil && lastAnalyzedHash != nil)
                ? DHashComputer.distance(lastAnalyzedHash!, hash!)
                : NSNull(),
            "hash": hash?.hexString ?? NSNull(),
            "front": front?.appName ?? NSNull(),
            "ai_level": ai?.level.rawValue ?? NSNull(),
            "ai_reasoning": ai?.reasoning ?? NSNull(),
            "latency_ms": latencyMs
        ]
        if let data = try? JSONSerialization.data(withJSONObject: entry),
           let str = String(data: data, encoding: .utf8) {
            appendDiagnostic(str + "\n")
        }

        return FrameTickResult(
            decision: decision,
            image: image,
            hash: hash,
            front: front,
            ai: ai,
            latencyMs: latencyMs,
            hasChanged: hasChanged,
            at: now,
            lastKnownLevel: lastLevel
        )
    }

    private func appendDiagnostic(_ line: String) {
        // 简单 append，错误忽略——诊断不应影响主流程
        if let h = try? FileHandle(forWritingTo: diagnosticLogURL) {
            do {
                _ = try h.seekToEnd()
                try h.write(contentsOf: Data(line.utf8))
                try h.close()
            } catch {
                // 忽略写盘失败
            }
        } else {
            try? line.write(to: diagnosticLogURL, atomically: true, encoding: .utf8)
        }
    }

    private func decisionName(_ d: FrameDecision) -> String {
        switch d {
        case .skippedIdle: return "skipped_idle"
        case .skippedNoWindows: return "skipped_no_windows"
        case .skippedAIBusy: return "skipped_ai_busy"
        case .skippedDhashStable: return "skipped_dhash_stable"
        case .analyzed(let r, _, _, let fromAI):
            return "analyzed_\(r.rawValue)_\(fromAI ? "ai" : "fallback")"
        }
    }

    private func encodeJPEG(_ image: CGImage) async throws -> Data {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        try await MainActorBridge.runAsync {
            try ScreenCaptureManager().encodeAndWrite(image, to: tempURL)
        }
        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return data
    }
}

/// 单次 tick 的返回，上层把它转成 AnalysisRecord 落库。
struct FrameTickResult: Sendable {
    let decision: FrameDecision
    /// CGImage 不是 Sendable，但 actor 内部已转 jpeg；这里只在测试时观察用，生产中标 nil
    let image: CGImage?
    let hash: Data?
    let front: FrontAppDetector.Result?
    let ai: FrameAnalysis?
    let latencyMs: Int
    let hasChanged: Bool
    let at: Date
    /// 距上次"已被 AI 判定"的 level；用于复用分支正确填 level
    let lastKnownLevel: FocusLevel?
}

/// 让 actor 调 @MainActor 函数的小帮手，避免到处 await MainActor.run。
enum MainActorBridge {
    static func runSync<T: Sendable>(_ body: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { body() }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { body() }
            }
        }
    }

    static func runAsync<T: Sendable>(_ body: @MainActor @Sendable () throws -> T) async throws -> T {
        try await MainActor.run { try body() }
    }
}
