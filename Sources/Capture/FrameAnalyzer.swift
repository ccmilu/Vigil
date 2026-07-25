import Foundation
import CoreGraphics
import OSLog

/// 5 闸门决策流，每 tickInterval 跑一次：
///
/// 1. idle（用户长时间无输入）→ 标 idle，不调 AI
/// 2. 截屏失败 / 桌面 only / 无窗口 → skip
/// 3. AI 仍在跑 → skip 这一帧；否则截全部显示器（minX 升序）
/// 4. dHash 多屏求值：每屏各算 hash，max 距离 < 阈值 且 距上次 AI 不到 maxAIInterval → skip
/// 5. 否则调 AI 分析这一帧（多图消息：每屏一张图，minX 序；落库 dhashHex/dhashDistance 记 max 屏的值）
///
/// 同时把每一帧的诊断（含 dHash / 距离 / 决策原因）写到本地 jsonl，用于日后调参。
actor FrameAnalyzer {

    private let service: AIService
    private let capture: ScreenCaptureManager
    private let config: CaptureConfig
    private let sessionID: UUID
    private let diagnosticLogURL: URL

    private var lastAnalyzedHashes: [CGDirectDisplayID: Data] = [:]
    private var lastAnalyzedAt: Date?
    private var lastLevel: FocusLevel?
    private var isAIBusy = false

    private let logger = Logger(subsystem: "com.jason12138.focus", category: "FrameAnalyzer")
    private let isoFormatter = ISO8601DateFormatter()

    /// 上层喂入的会话上下文（promise + 是否暂停等），用 actor 内部状态隔离。
    private var currentPromise: String
    /// 本 session 整段持续使用的 AI 回复语言（在 start 时由 SessionManager 快照），
    /// 即使用户中途在 Settings 改语言也不影响进行中 session 的 AI 输出风格。
    private let responseLanguage: String

    init(
        service: AIService,
        capture: ScreenCaptureManager = ScreenCaptureManager(),
        config: CaptureConfig = .default,
        sessionID: UUID,
        promise: String,
        diagnosticLogURL: URL,
        responseLanguage: String = kDefaultAIResponseLanguage
    ) {
        self.service = service
        self.capture = capture
        self.config = config
        self.sessionID = sessionID
        self.currentPromise = promise
        self.diagnosticLogURL = diagnosticLogURL
        self.responseLanguage = responseLanguage
    }

    func setPromise(_ p: String) { currentPromise = p }

    // MARK: - 主入口：一帧

    /// 调用一次决策流，返回这帧的决策与可能的 AnalysisRecord 字段。
    /// `now` 注入便于测试。`captureOverride` 让测试可以不依赖真截屏（返回各屏帧，minX 升序）。
    func tick(
        now: Date = .now,
        captureOverride: ((@Sendable () async throws -> [DisplayFrame])?) = nil
    ) async -> FrameTickResult {
        // Gate 1: idle
        let idleSec = MainActorBridge.runSync { IdleDetector.secondsSinceLastInput() }
        if idleSec >= config.idleThreshold {
            // 关键：lastLevel 也要切到 .idle，否则 distract → idle → distract 的回程
            // 会因 lastLevel 仍是 .distracted 算成 "未跳变"，SessionManager 不弹遮罩
            lastLevel = .idle
            return await record(.skippedIdle(seconds: idleSec), at: now)
        }

        // Gate 2: AI 排队
        if isAIBusy {
            return await record(.skippedAIBusy, at: now)
        }

        // Gate 3: 截屏（全显示器，minX 升序；含 desktop-only / no-windows 判定）
        let frames: [DisplayFrame]
        do {
            if let override = captureOverride {
                frames = try await override()
            } else {
                frames = try await capture.captureAllDisplays()
            }
        } catch ScreenCaptureManager.CaptureError.desktopOnly,
                ScreenCaptureManager.CaptureError.noDisplay {
            return await record(.skippedNoWindows, at: now)
        } catch {
            logger.error("截屏失败：\(error.localizedDescription)")
            return await record(.skippedNoWindows, at: now)
        }
        // 空数组保护（captureOverride 理论上可返回空；captureAllDisplays 空时自己抛错）
        guard !frames.isEmpty else {
            return await record(.skippedNoWindows, at: now)
        }

        // Gate 4: dHash 变化检测（多屏：每屏各算 hash，max 距离与阈值比较）+ 时间兜底
        var newHashes: [CGDirectDisplayID: Data] = [:]
        for frame in frames {
            newHashes[frame.displayID] = DHashComputer.hash(frame.image)
        }
        // 空字典必须等价旧版 nil（firstFrame 语义）——否则"空 old"会算出 distance=0 误跳首帧
        let isFirstFrame = lastAnalyzedHashes.isEmpty
        let hashEval = MultiDisplayDHash.distances(
            old: isFirstFrame ? nil : lastAnalyzedHashes,
            new: newHashes
        )
        // 落库 / 诊断日志统一记 max 屏的哈希（maxDisplayID 必为 new 的 key，frames 非空时必有值）
        let maxHash = hashEval.maxDisplayID.flatMap { newHashes[$0] }

        var distance: Int? = nil
        var reason: FrameDecision.AnalysisReason
        if !isFirstFrame {
            let d = hashEval.max
            distance = d
            let timedOut = lastAnalyzedAt.map { now.timeIntervalSince($0) >= config.maxAIInterval } ?? true
            if d < config.dhashThreshold && !timedOut {
                // dHash skip 不更新 hash 字典（现状语义保留）
                return await record(.skippedDhashStable(distance: d), at: now, images: frames, hash: maxHash)
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
        // 逐屏编码 JPEG（各自 try? 容错，单屏失败只少一张图，不影响其余屏）；
        // 全部失败才走"编码失败回落 lastLevel"分支（不更新 hash，下帧重试编码）
        var jpegs: [Data] = []
        jpegs.reserveCapacity(frames.count)
        for frame in frames {
            if let data = try? ScreenCaptureManager.jpegData(frame.image) {
                jpegs.append(data)
            }
        }
        guard !jpegs.isEmpty else {
            logger.error("JPEG 编码失败：全部 \(frames.count) 块显示器均编码失败")
            return await record(
                .analyzed(reason: reason, distance: distance, level: lastLevel ?? .wandering, fromAI: false),
                at: now, images: frames, hash: maxHash
            )
        }
        do {
            // 任务级硬超时（取自 config，可在 Settings 调）。
            let hardTimeout = config.aiHardTimeout
            let result = try await withThrowingTaskGroup(of: FrameAnalysis.self) { group in
                group.addTask { [service, currentPromise, front, jpegs, responseLanguage] in
                    try await service.analyzeFrame(
                        FrameAnalysisInput(
                            promise: currentPromise,
                            appName: front.appName,
                            windowTitles: front.windowTitles,
                            screenshotJPEGs: jpegs,
                            responseLanguage: responseLanguage
                        )
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(hardTimeout * 1_000_000_000))
                    throw AIServiceError.network(URLError(.timedOut))
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            // F1 修复：首帧 lastLevel==nil 时，若 AI 返回非 fully 状态也应视为"跳变进入非专注"。
            // 设计意图：首帧是从"未知"进入某个 level，只要结果不是 fully（即不是"正常专注"）
            // 就通知上层做出响应，避免遮罩在首帧分心时永不弹出。
            // 首帧且结果为 fully 时 hasChanged=false，不触发遮罩（正常起步专注，无需打扰）。
            let hasChanged: Bool
            if let prev = lastLevel {
                hasChanged = prev != result.level
            } else {
                // 首帧：非 fully 算"跳变进入非专注状态"
                hasChanged = result.level != .fully
            }
            lastAnalyzedHashes = newHashes  // 整字典替换：已拔除的屏自动剪枝
            lastAnalyzedAt = now
            lastLevel = result.level
            return await record(
                .analyzed(reason: reason, distance: distance, level: result.level, fromAI: true),
                at: now, images: frames, hash: maxHash,
                front: front, ai: result, latencyMs: latency, hasChanged: hasChanged,
                diagnosticDistance: distance
            )
        } catch {
            logger.error("AI 分析失败：\(error.localizedDescription)")
            // AI 失败：复用上次 level（如果有），fromAI=false
            let level = lastLevel ?? .wandering
            lastAnalyzedHashes = newHashes
            lastAnalyzedAt = now
            return await record(
                .analyzed(reason: reason, distance: distance, level: level, fromAI: false),
                at: now, images: frames, hash: maxHash, front: front, diagnosticDistance: distance
            )
        }
    }

    // MARK: - 记录器

    private func record(
        _ decision: FrameDecision,
        at now: Date,
        images: [DisplayFrame] = [],
        hash: Data? = nil,
        front: FrontAppDetector.Result? = nil,
        ai: FrameAnalysis? = nil,
        latencyMs: Int = 0,
        hasChanged: Bool = false,
        // F7 修复：由 tick() 将已算好的 distance 传入，record() 不再重算。
        // 重算的问题：tick() 在调 record() 前已执行 lastAnalyzedHashes = newHashes，
        // 导致 distance(lastHash, newHash) = distance(hash, hash) = 0，恒为 0。
        // skippedIdle / skippedNoWindows / skippedAIBusy 等跳过路径传 nil，日志字段为 null。
        diagnosticDistance: Int? = nil
    ) async -> FrameTickResult {
        // 写诊断日志
        let entry: [String: Any] = [
            "ts": isoFormatter.string(from: now),
            "sessionID": sessionID.uuidString,
            "decision": decisionName(decision),
            "distance": diagnosticDistance.map { $0 as Any } ?? NSNull(),
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
            images: images,
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
}

/// 单次 tick 的返回，上层把它转成 AnalysisRecord 落库。
struct FrameTickResult: Sendable {
    let decision: FrameDecision
    /// 本帧各屏截图（minX 升序）。skippedIdle / skippedNoWindows / skippedAIBusy 等决策为空数组。
    /// CGImage 在 actor 内部已转 jpeg；这里供 persistTick 逐屏落盘与测试观察。
    let images: [DisplayFrame]
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
