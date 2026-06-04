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

        /// 当前阶段是否允许开新 session。preparing / running / resting / analyzing
        /// 期间禁止再起，避免覆盖在跑的 session 状态。
        var allowsNewSession: Bool {
            switch self {
            case .idle, .completed, .failed: return true
            case .preparing, .running, .resting, .analyzing: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastAnalysis: AnalysisRecord?

    private let modelContainer: ModelContainer
    private let serviceFactory: @MainActor (AIDebugSink?) -> AIService
    /// internal 以便 @testable import 测试验证 F11（convenience init 使用 AppSettings.shared）
    let settings: AppSettings
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

    /// 30s 间歇计时的基准时刻——**遮罩"关闭"的瞬间**（点按钮 / 自动关）。
    /// 弹窗期间被设为 .distantFuture 防止重复触发；遮罩关掉后置为当前时间，
    /// 之后再过 distractReminderInterval 才会再弹下一个。
    /// 跳出 distract 时清空。
    /// internal（非 private）以便 @testable import 单元测试验证跨 session 状态隔离（F4）。
    var distractCooldownUntil: Date?
    /// 上次 distract 时 AI 给的 reminder 文案；持续分心再弹时复用（dhash skip 帧没新文案）
    var lastDistractReminder: String = ""
    /// 当前一段连续 distract 已经弹了多少次。跳出 distract 时归零。
    /// 第 3 次起遮罩多一个"AI 可能误判，本次分心不再提醒"按钮。
    var distractAlertCount: Int = 0
    /// 用户点过"本次分心不再提醒"——保持到跳出 distract 为止。
    var distractSuppressedInStreak: Bool = false
    /// 弹到第几次起显示"本次分心不再提醒"兜底按钮
    private static let distractSuppressThreshold: Int = 3

    // idle / wandering 软提醒状态
    var idleStreakStartedAt: Date?
    var idleNextSoundAt: Date?
    var wanderingStreakStartedAt: Date?
    /// wandering 下次允许弹刘海提醒的时刻；nil = 还没弹过（首次到阈值就弹）
    var wanderingNextAlertAt: Date?

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
    /// F11 修复：改用 AppSettings.shared 而非 AppSettings()，
    /// 避免 convenience init 创建孤立实例违反 singleton 约束。
    convenience init(
        modelContainer: ModelContainer,
        service: AIService
    ) {
        self.init(
            modelContainer: modelContainer,
            settings: AppSettings.shared,
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
    /// F5 修复：不再覆盖 self.service（validatePromise 与 start 共用的 self.service 赋值
    /// 应只在 start() 里做，让 serviceFactory 和 debugSink 在真正起 session 时生效）。
    /// validatePromise 构造临时的 service 实例：debug 开启时写到独立的
    /// promise-validation 目录（不影响主 session 目录），关闭时 sink 为 nil。
    func validatePromise(_ promise: String) async -> PromiseValidation {
        // F5：构造 promise 校验阶段的 debug sink，和 session 目录隔离
        let validationSink: AIDebugSink? = {
            guard settings.debugEnabled else { return nil }
            let dir = ScreenshotStore.rootDirectory
                .appendingPathComponent("validation")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ts = Int(Date().timeIntervalSince1970)
            return AIDebugSink(url: dir.appendingPathComponent("promise-\(ts).jsonl"))
        }()
        // 构造一次性的临时 service，不覆写 self.service
        let tempService = serviceFactory(validationSink)
        do {
            let result = try await tempService.analyzeTask(promise)
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
        // 防御性 guard：上层入口（PromisePanel）已拦，这里兜底防止并发开 session
        guard phase.allowsNewSession else {
            return .failure(NSError(
                domain: "FocusSession",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "已有专注进行中，无法开新 session"]
            ))
        }
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

    /// F4 修复：统一重置所有 per-session 提醒状态。
    /// 在 endSession 末尾调用，确保下一 session 第一帧的 distract/idle/wandering
    /// 状态不会受上一 session 残留影响（否则 distractCooldownUntil=.distantFuture
    /// 或 distractSuppressedInStreak=true 会导致整段 distract 静默）。
    private func resetPerSessionAlertState() {
        distractCooldownUntil = nil
        lastDistractReminder = ""
        distractAlertCount = 0
        distractSuppressedInStreak = false
        idleStreakStartedAt = nil
        idleNextSoundAt = nil
        wanderingStreakStartedAt = nil
        wanderingNextAlertAt = nil
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

        // 算时间分布（每条 AnalysisRecord 视作 captureInterval 秒）
        // 注意：分母用 records.count × perRecord 而非 actualDuration——
        // .skippedNoWindows / .skippedAIBusy / preparing 阶段不入库，
        // 用 actualDuration 当分母会让 4 个 ratio 总和 < 100%，柱状图右边出现空白
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
        let observed = max(Double(records.count) * perRecord, 1)
        s.fullyRatio = fully / observed
        s.wanderingRatio = wandering / observed
        s.distractedRatio = distracted / observed
        s.idleRatio = idle / observed

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
        // F4 修复：清理所有 per-session 提醒状态，防止残留影响下一 session
        resetPerSessionAlertState()
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
        // F3 修复：AI 任务飞行期间 endSession 可能已将 phase 切到 .analyzing 或之后。
        // 此时 stopTicking 只 cancel task 不 await，in-flight 的 analyzeFrame 网络请求
        // 会在 summarize 期间回来并走 persistTick → maybeAlertDistraction，
        // 导致在复盘页弹出 DistractOverlay。此 guard 在 await 返回后二次检查 phase，
        // 非 running 时直接丢弃结果，不落库也不触发任何提醒。
        guard case .running = phase else { return }
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
            await maybeAlertDistraction(level: .idle, hasChanged: false, newReminder: nil, promise: session.promise)
            maybeAlertIdle(level: .idle)
            maybeAlertWandering(level: .idle)
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
            // dhash skip 不算 level 跳变，但所有提醒计时仍然要 tick
            await maybeAlertDistraction(level: reusedLevel, hasChanged: false, newReminder: nil, promise: session.promise)
            maybeAlertIdle(level: reusedLevel)
            maybeAlertWandering(level: reusedLevel)
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
            await maybeAlertDistraction(
                level: level,
                hasChanged: result.hasChanged,
                newReminder: result.ai?.reminder,
                promise: session.promise
            )
            maybeAlertIdle(level: level)
            maybeAlertWandering(level: level)
        }
        ctx.insert(record)
        try? ctx.save()
        self.lastAnalysis = record
        // 同步推一条到刘海岛 timeline，让 TimelineBar 实时更新
        NotchTimer.shared.appendAnalysis(at: record.createdAt, level: record.level)
    }

    /// 统一的 distract 提醒入口：
    /// - 跳变进入 distract（hasChanged）→ 立刻弹
    /// - 持续 distract 且**已过 cooldown**（now ≥ distractCooldownUntil）→ 再弹一次
    /// - 离开 distract → 清空 cooldown 和 reminder 文案，让下次进 distract 算"首次"
    ///
    /// 触发弹窗时把 cooldownUntil 设为 .distantFuture（弹窗期间不重复触发），
    /// DistractOverlay.onClosed 回调里把它设为"now + interval"，
    /// 这样 30s 是从**遮罩关闭那一刻**开始算，不是弹窗瞬间——避免遮罩刚关又立刻弹下一个。
    private func maybeAlertDistraction(
        level: FocusLevel,
        hasChanged: Bool,
        newReminder: String?,
        promise: String
    ) async {
        guard level == .distracted else {
            // 跳出 distract：所有 streak 状态归零，下次进 distract 算"首次"
            distractCooldownUntil = nil
            lastDistractReminder = ""
            distractAlertCount = 0
            distractSuppressedInStreak = false
            return
        }

        // 用户在当前 distract 区间按过"AI 误判，不再提醒"——直接静默到跳出 distract
        if distractSuppressedInStreak { return }

        let now = Date()
        let shouldAlert: Bool
        if hasChanged {
            shouldAlert = true  // 首次跳变必弹，不受 intervalEnabled 影响
        } else if !settings.distractIntervalEnabled {
            shouldAlert = false  // 关了间歇提醒，持续 distract 不再弹
        } else if let until = distractCooldownUntil, now >= until {
            shouldAlert = true
        } else {
            shouldAlert = false
        }
        guard shouldAlert else { return }

        // 新 reminder 非空就用新的，否则复用上次（dhash skip 帧没新文案）
        let reminder: String
        if let r = newReminder, !r.isEmpty {
            reminder = r
            lastDistractReminder = r
        } else {
            reminder = lastDistractReminder
        }
        distractAlertCount += 1
        let showSuppress = distractAlertCount >= Self.distractSuppressThreshold

        // 弹窗期间把 cooldown 推到很远，防止下一个 tick 又触发；
        // onClosed 回调里改成"now + interval"，从关闭瞬间开始计时
        distractCooldownUntil = .distantFuture
        let intervalSec = settings.distractIntervalSec
        DistractOverlay.shared.onClosed = { [weak self] in
            self?.distractCooldownUntil = Date().addingTimeInterval(TimeInterval(intervalSec))
        }
        DistractOverlay.shared.onSuppress = { [weak self] in
            self?.distractSuppressedInStreak = true
        }

        await Notifier.notifyDistraction(reminder: reminder)
        SoundPlayer.shared.play(.distract)
        NotchTimer.shared.flashDistracted(reminder: reminder)
        DistractOverlay.shared.present(
            reminder: reminder,
            promise: promise,
            showSuppress: showSuppress
        )
    }

    /// 长时间 idle（不在电脑前）软提醒：刘海岛展开 + 周期性声音召回
    private func maybeAlertIdle(level: FocusLevel) {
        guard settings.idleAlertEnabled else {
            idleStreakStartedAt = nil
            idleNextSoundAt = nil
            return
        }
        guard level == .idle else {
            // 跳出 idle = 用户回来动了一下，立刻停
            if idleStreakStartedAt != nil {
                NotchTimer.shared.stopSoftReminder()
            }
            idleStreakStartedAt = nil
            idleNextSoundAt = nil
            return
        }
        let now = Date()
        if idleStreakStartedAt == nil { idleStreakStartedAt = now }
        guard let start = idleStreakStartedAt else { return }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= TimeInterval(settings.idleAlertThresholdSec) else { return }

        // 已进入 idle 软提醒：首次弹刘海 + 声音；之后每 idleAlertRepeatSec 重弹声音
        if NotchTimer.shared.softReminderLevel != .idle {
            NotchTimer.shared.flashIdle(message: "似乎不在电脑前 · 回来一下？")
            SoundPlayer.shared.play(.distract)
            idleNextSoundAt = now.addingTimeInterval(TimeInterval(settings.idleAlertRepeatSec))
        } else if let next = idleNextSoundAt, now >= next {
            SoundPlayer.shared.play(.distract)
            idleNextSoundAt = now.addingTimeInterval(TimeInterval(settings.idleAlertRepeatSec))
        }
    }

    /// 持续 wandering（边缘走神）超阈值时弹刘海软提醒，并每 intervalSec 重弹
    private func maybeAlertWandering(level: FocusLevel) {
        guard settings.wanderingAlertEnabled else {
            wanderingStreakStartedAt = nil
            wanderingNextAlertAt = nil
            return
        }
        guard level == .wandering else {
            wanderingStreakStartedAt = nil
            wanderingNextAlertAt = nil
            return
        }
        let now = Date()
        if wanderingStreakStartedAt == nil { wanderingStreakStartedAt = now }
        guard let start = wanderingStreakStartedAt else { return }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= TimeInterval(settings.wanderingAlertThresholdSec) else { return }
        // 首次到阈值（nextAlertAt==nil）必弹；之后每 intervalSec 才允许下一次
        if let next = wanderingNextAlertAt, now < next { return }
        NotchTimer.shared.flashWandering(message: "走神时间有点长 · 回到正事吗？")
        wanderingNextAlertAt = now.addingTimeInterval(TimeInterval(settings.wanderingAlertIntervalSec))
    }
}
