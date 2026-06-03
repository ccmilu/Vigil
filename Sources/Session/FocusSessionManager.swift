import Foundation
import SwiftData
import SwiftUI
import Combine
import OSLog

/// 把 promise → 截屏 → AI → 通知 串成完整 Session。
/// 状态机：
///   idle → preparing (analyzeTask) → running → analyzing (summarize) → completed
///
/// 责任：
/// - 起 session、记 plannedDuration、timer 倒计时
/// - 驱动 FrameAnalyzer 每 5s 跑一次
/// - 拿到 AnalysisRecord 落 SwiftData + 触发 distract 通知
/// - 结束时算时间分布、调 summarize、写回 FocusSession
@MainActor
final class FocusSessionManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing(promise: String)
        case running(promise: String, remaining: TimeInterval)
        case resting(remaining: TimeInterval)
        case analyzing
        case completed(sessionID: UUID)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastAnalysis: AnalysisRecord?

    private let modelContainer: ModelContainer
    private let serviceFactory: @MainActor (AIDebugSink?) -> AIService
    private let settings: AppSettings
    private var service: AIService
    private var analyzer: FrameAnalyzer?
    private var session: FocusSession?

    private var timer: Timer?
    private var tickTimer: Timer?
    private var startedAt: Date?
    /// 当前活跃 session 的 capture 配置（在 start 时根据 settings 计算）
    private var activeCaptureConfig: CaptureConfig = .default
    /// 一次只允许一个 tick 在跑；若 tick 期间又触发，标记 pending 待 AI 完成立即续跑
    private var currentTickTask: Task<Void, Never>?
    private var pendingTickWanted = false

    private let logger = Logger(subsystem: "com.jason12138.focus", category: "Session")

    init(
        modelContainer: ModelContainer,
        settings: AppSettings = AppSettings(),
        serviceFactory: @escaping @MainActor (AIDebugSink?) -> AIService = { sink in
            OpenAICompatibleService(debugSink: sink)
        }
    ) {
        self.modelContainer = modelContainer
        self.settings = settings
        self.serviceFactory = serviceFactory
        self.service = serviceFactory(nil)
    }

    /// 测试便捷构造器：直接注入固定 service。
    convenience init(
        modelContainer: ModelContainer,
        service: AIService
    ) {
        self.init(
            modelContainer: modelContainer,
            settings: AppSettings(),
            serviceFactory: { _ in service }
        )
    }

    func reset() {
        phase = .idle
    }

    /// 通过 setter 暴露，让 ContentView 在休息结束时弹出 Promise 面板
    var onBreakFinished: (@MainActor () -> Void)?

    /// 开始一段休息（不截屏、不调 AI），到时通知 + 召唤 Promise 面板。
    func startBreak(durationSeconds: Int) {
        stopCountdown()
        stopTicking()
        phase = .resting(remaining: TimeInterval(durationSeconds))
        DockBadge.setRemaining(seconds: durationSeconds)
        let end = Date().addingTimeInterval(TimeInterval(durationSeconds))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard case .resting = self.phase else { return }
                let remaining = end.timeIntervalSinceNow
                if remaining <= 0 {
                    self.stopCountdown()
                    DockBadge.setRemaining(seconds: nil)
                    await Notifier.notifyBreakEnd()
                    self.phase = .idle
                    self.onBreakFinished?()
                } else {
                    self.phase = .resting(remaining: remaining)
                    DockBadge.setRemaining(seconds: Int(remaining))
                }
            }
        }
    }

    /// 提前结束休息（绕过倒计时）。UI 应做二次确认。
    func abortBreak() {
        stopCountdown()
        DockBadge.setRemaining(seconds: nil)
        phase = .idle
    }

    // MARK: - 起 session

    /// 起一次会话；成功返回 sessionID。
    /// promise 校验的三种结果
    enum PromiseValidation {
        case clear                          // 通过校验
        case needsClarification(String)     // AI 反问，需要改 promise
        case serviceUnreachable(String)     // AI 服务不通；UI 应阻塞 + 提示 + 允许"离线启动"
    }

    /// 校验 promise + 顺带探活 AI 服务。
    func validatePromise(_ promise: String) async -> PromiseValidation {
        self.service = serviceFactory(nil)
        do {
            let result = try await service.analyzeTask(promise)
            if let s = result.suggestion, !s.isEmpty {
                return .needsClarification(s)
            }
            return .clear
        } catch {
            logger.warning("analyzeTask 失败：\(error.localizedDescription)")
            return .serviceUnreachable((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    @discardableResult
    func start(promise: String, durationSeconds: Int) async -> Result<UUID, Error> {
        phase = .preparing(promise: promise)

        // 建 SwiftData session
        let ctx = modelContainer.mainContext
        let s = FocusSession(promise: promise, plannedDuration: durationSeconds)
        ctx.insert(s)
        do {
            try ctx.save()
        } catch {
            phase = .failed("无法保存 session：\(error.localizedDescription)")
            return .failure(error)
        }
        self.session = s
        self.startedAt = .now
        phase = .running(promise: promise, remaining: TimeInterval(durationSeconds))

        // 准备 debug sink（若开启），路径写在该 session 目录
        let sessionDir = ScreenshotStore.rootDirectory.appendingPathComponent(s.id.uuidString)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let debugSink: AIDebugSink? = settings.debugEnabled
            ? AIDebugSink(url: sessionDir.appendingPathComponent("prompts.jsonl"))
            : nil
        // 每次起 session 都重新拿 service（用户可能在 Settings 换了 provider）
        self.service = serviceFactory(debugSink)

        // 起 FrameAnalyzer
        self.activeCaptureConfig = settings.makeCaptureConfig()
        let logURL = sessionDir.appendingPathComponent("diagnostic.jsonl")
        self.analyzer = FrameAnalyzer(
            service: service,
            config: activeCaptureConfig,
            sessionID: s.id,
            promise: promise,
            diagnosticLogURL: logURL
        )

        startCountdown(durationSeconds: durationSeconds)
        startTicking()
        DockBadge.setRemaining(seconds: durationSeconds)
        NotchTimer.shared.update(remaining: TimeInterval(durationSeconds), level: nil)
        NotchTimer.shared.show(promise: promise, plannedSeconds: durationSeconds)
        SoundPlayer.shared.play(.start)

        return .success(s.id)
    }

    // MARK: - 停止 session

    func stopManually(reason: String? = nil) async {
        await endSession(status: .manualCompleted, stopReason: reason)
    }

    private func autoComplete() async {
        await endSession(status: .autoCompleted, stopReason: nil)
    }

    private func endSession(status: SessionStatus, stopReason: String?) async {
        guard let s = session else { return }
        stopCountdown()
        stopTicking()
        DockBadge.setRemaining(seconds: nil)
        NotchTimer.shared.hide()
        phase = .analyzing

        let actual = startedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        s.actualDuration = actual
        s.endedAt = .now
        s.status = status
        s.stopReason = stopReason

        // 算时间分布（每条 AnalysisRecord 视作 captureInterval 秒，简单近似）
        let ctx = modelContainer.mainContext
        let sid = s.id
        let descriptor = FetchDescriptor<AnalysisRecord>(
            predicate: #Predicate { $0.session?.id == sid }
        )
        let records = (try? ctx.fetch(descriptor)) ?? []
        let perRecord = activeCaptureConfig.tickInterval
        var fully = 0.0, wandering = 0.0, distracted = 0.0, idle = 0.0
        for r in records {
            switch r.level {
            case .fully: fully += perRecord
            case .wandering: wandering += perRecord
            case .distracted: distracted += perRecord
            case .idle: idle += perRecord
            }
        }
        let total = max(Double(actual), 1)
        s.fullyRatio = fully / total
        s.wanderingRatio = wandering / total
        s.distractedRatio = distracted / total
        s.idleRatio = idle / total

        // 调 summarize
        let distractedNotes = records.filter { $0.level == .distracted }.map(\.reasoning)
        do {
            let text = try await service.summarize(
                SummaryInput(
                    promise: s.promise,
                    sessionSeconds: actual,
                    fullySec: Int(fully),
                    wanderingSec: Int(wandering),
                    distractedSec: Int(distracted),
                    idleSec: Int(idle),
                    distractedNotes: distractedNotes
                )
            )
            s.summary = text
        } catch {
            logger.warning("summarize 失败：\(error.localizedDescription)")
            s.summary = "(AI 复盘失败：\(error.localizedDescription))"
        }
        try? ctx.save()

        // 更新 Streak（实际时长 ≥ 5min 才计入）
        StreakUpdater.recordCompletion(
            sessionSeconds: actual,
            in: modelContainer
        )

        phase = .completed(sessionID: s.id)
        self.session = nil
        self.analyzer = nil
        self.startedAt = nil
        SoundPlayer.shared.play(.complete)
    }

    // MARK: - 倒计时

    private func startCountdown(durationSeconds: Int) {
        let end = Date().addingTimeInterval(TimeInterval(durationSeconds))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard case .running(let p, _) = self.phase else { return }
                let remaining = end.timeIntervalSinceNow
                if remaining <= 0 {
                    await self.autoComplete()
                } else {
                    self.phase = .running(promise: p, remaining: remaining)
                    DockBadge.setRemaining(seconds: Int(remaining))
                    NotchTimer.shared.update(
                        remaining: remaining,
                        level: self.lastAnalysis?.level
                    )
                }
            }
        }
    }

    private func stopCountdown() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - tick FrameAnalyzer

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(
            withTimeInterval: activeCaptureConfig.tickInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestTick()
            }
        }
        // 也跑一次立刻的，避免等 5s
        requestTick()
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
        currentTickTask?.cancel()
        currentTickTask = nil
        pendingTickWanted = false
    }

    /// 触发一次 tick 请求。串行执行：
    /// - 没有 in-flight：立即起 task 跑
    /// - 有 in-flight：标记 pending，当前 task 跑完会立即续一次
    ///   多个 tick 在 in-flight 期间堆叠时只保留 1 个 pending（latest-only，
    ///   避免 AI 持续慢时积压无限多个任务）
    private func requestTick() {
        guard analyzer != nil, session != nil else { return }
        if currentTickTask != nil {
            pendingTickWanted = true
            return
        }
        startTickTask()
    }

    private func startTickTask() {
        currentTickTask = Task { [weak self] in
            guard let self else { return }
            await self.runOneTickInner()
            await MainActor.run {
                self.currentTickTask = nil
                // AI 完成后检查 pending：若期间有 tick 想跑，立即续一帧
                if self.pendingTickWanted {
                    self.pendingTickWanted = false
                    self.startTickTask()
                }
            }
        }
    }

    private func runOneTickInner() async {
        guard let analyzer = analyzer, let s = session else { return }
        let result = await analyzer.tick()
        await persistTick(result: result, session: s)
    }

    private func persistTick(result: FrameTickResult, session: FocusSession) async {
        // 写盘 + 落 AnalysisRecord
        let ctx = modelContainer.mainContext
        var screenshotPath: String? = nil
        if let image = result.image {
            // 仅在 analyzed 分支落盘；skip 不存
            if case .analyzed = result.decision {
                let (url, relative) = ScreenshotStore.newScreenshotURL(sessionID: session.id, at: result.at)
                try? ScreenCaptureManager().encodeAndWrite(image, to: url)
                screenshotPath = relative
            }
        }

        let record: AnalysisRecord
        switch result.decision {
        case .skippedIdle:
            record = AnalysisRecord(
                session: session,
                frontAppName: result.front?.appName ?? "",
                frontWindowTitles: result.front?.windowTitles ?? "",
                level: .idle, reasoning: "", reminder: "",
                fromAI: false, hasChanged: false,
                dhashHex: result.hash?.hexString,
                createdAt: result.at
            )
        case .skippedNoWindows, .skippedAIBusy:
            return  // 这两种情况不入库，避免噪声
        case .skippedDhashStable(let dist):
            // 复用上次 AI 判定的真实 level（之前硬编码 .wandering 是 bug）
            let reusedLevel = result.lastKnownLevel ?? .wandering
            record = AnalysisRecord(
                session: session,
                screenshotLocalPath: screenshotPath,
                frontAppName: result.front?.appName ?? "",
                frontWindowTitles: result.front?.windowTitles ?? "",
                level: reusedLevel,
                reasoning: "(画面无显著变化，复用上次判断)",
                reminder: "",
                fromAI: false, hasChanged: false,
                dhashHex: result.hash?.hexString,
                dhashDistance: dist,
                createdAt: result.at
            )
        case .analyzed(_, let dist, let level, let fromAI):
            record = AnalysisRecord(
                session: session,
                screenshotLocalPath: screenshotPath,
                frontAppName: result.front?.appName ?? "",
                frontWindowTitles: result.front?.windowTitles ?? "",
                level: level,
                reasoning: result.ai?.reasoning ?? "",
                reminder: result.ai?.reminder ?? "",
                fromAI: fromAI,
                hasChanged: result.hasChanged,
                dhashHex: result.hash?.hexString,
                dhashDistance: dist,
                createdAt: result.at,
                analysisLatencyMs: result.latencyMs
            )
            // 每帧 AI 返回都更新刘海岛展示的活动描述
            if fromAI, let ai = result.ai {
                NotchTimer.shared.updateAIFeedback(reasoning: ai.reasoning)
            }

            // 状态变化打通知 + 提示音 + 全屏遮罩 + 刘海 pulse
            if result.hasChanged, level == .distracted {
                let reminder = result.ai?.reminder ?? ""
                await Notifier.notifyDistraction(reminder: reminder)
                SoundPlayer.shared.play(.distract)
                NotchTimer.shared.flashDistracted(reminder: reminder)
                DistractOverlay.shared.present(
                    reminder: reminder,
                    promise: session.promise
                )
            }
        }
        ctx.insert(record)
        try? ctx.save()
        self.lastAnalysis = record
    }
}
