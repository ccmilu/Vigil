import Foundation
import OSLog
import SwiftData

/// 一次性数据迁移。每次新增迁移加一个 UserDefaults 标志位，run 完置 true。
///
/// 关于 perRecord（5.0 秒）：
/// 项目 tick 间隔固定为 5 秒（CaptureConfig.tickInterval）。每条 AnalysisRecord 对应
/// 一个 tick，因此 records.count × 5 可作为实际专注时长的保守估算。
@MainActor
enum Migrations {

    private static let logger = Logger(subsystem: "com.milu.Focus", category: "Migrations")

    /// v1：把所有历史 session 的 4 个 ratio 用新公式（分母 = records 数 × 5s）重算。
    /// 旧公式分母用 actualDuration，导致 .skippedNoWindows 等不入库的 tick 让总和 < 100%，
    /// 柱状图右边出现空白。
    private static let key_ratioRecalcV1 = "migration.ratioRecalc.v1.done"

    /// v2：首次启动时 seed 5 个默认 PlayTimer（10/15/25/45/60 分钟，slot=0-4）。
    /// 仅当 PlayTimer 表为空时执行，保护用户后续可能的自定义数据。
    /// TODO: 未来扩展到 9 预设时新增 key_seedDefaultPlayTimersV2，不改 V1 key。
    private static let key_seedDefaultPlayTimersV1 = "migration.seedDefaultPlayTimers.v1.done"

    /// 默认时长预设（分钟），slot 与数组下标一一对应
    static let defaultPresetMinutes = [10, 15, 25, 45, 60]

    static func runAll(container: ModelContainer) {
        // 一次性数据迁移
        if !UserDefaults.standard.bool(forKey: key_ratioRecalcV1) {
            recalcAllSessionRatios(container: container)
            UserDefaults.standard.set(true, forKey: key_ratioRecalcV1)
        }
        if !UserDefaults.standard.bool(forKey: key_seedDefaultPlayTimersV1) {
            seedDefaultPlayTimers(container: container)
            UserDefaults.standard.set(true, forKey: key_seedDefaultPlayTimersV1)
        }
        // 每次启动跑：回收上次没正常结束的僵尸 session
        reapStaleSessions(container: container)
    }

    /// 首次启动时 seed 默认 PlayTimer 预设。
    /// 幂等：PlayTimer 表非空时直接跳过，避免覆盖用户已有自定义数据。
    static func seedDefaultPlayTimers(container: ModelContainer) {
        let ctx = container.mainContext
        let existing = (try? ctx.fetch(FetchDescriptor<PlayTimer>())) ?? []
        guard existing.isEmpty else {
            logger.info("[Migration] PlayTimer 表非空（\(existing.count) 条），跳过 seed")
            return
        }
        for (slot, minutes) in defaultPresetMinutes.enumerated() {
            let timer = PlayTimer(seconds: minutes * 60, slot: slot)
            ctx.insert(timer)
        }
        try? ctx.save()
        logger.info("[Migration] seedDefaultPlayTimers：插入 \(defaultPresetMinutes.count) 条默认预设")
    }

    /// 上次进程被强杀 / 直接退出时，正在跑的 session 残留 status=.running。
    /// 启动时扫描，标记 .abandoned，用最后一条 record 的时间补 endedAt / actualDuration / ratio
    private static func reapStaleSessions(container: ModelContainer) {
        let ctx = container.mainContext
        let runningRaw = SessionStatus.running.rawValue
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.statusRaw == runningRaw }
        )
        guard let sessions = try? ctx.fetch(descriptor), !sessions.isEmpty else { return }

        let perRecord = 5.0
        for s in sessions {
            // 最后一条 record 的时间 = 用户最后操作时刻；没 record 就 startedAt（=持续 0 秒）
            let lastTime = s.records.map(\.createdAt).max() ?? s.startedAt
            s.endedAt = lastTime

            // F12 修复：防止 NTP 校时（时钟回拨）导致 wall-clock 差为负，actualDuration 退化为 0。
            // 策略（方案 C）：优先使用 wall-clock 差（更精确），但仅在差值为正且合理（< 4 小时）时采用；
            // 否则降级为 records.count × perRecord（保守估算），并写 OSLog 警告以便排查。
            // 4 小时上限：避免把"App 上次长时间 suspend 而未退出"误算成超长 actualDuration。
            let wallClock = lastTime.timeIntervalSince(s.startedAt)
            let recordsBased = Double(s.records.count) * perRecord
            let maxReasonableSeconds = 4.0 * 3600   // 4 小时
            if wallClock > 0 && wallClock <= maxReasonableSeconds {
                s.actualDuration = Int(wallClock)
            } else {
                // wall-clock 为负（时钟回拨）或超出合理范围（App 长时间 suspend 后被回收）
                s.actualDuration = Int(recordsBased)
                logger.warning("[Reaper] session \(s.id) wall-clock diff \(wallClock)s 不合理，降级使用 records×5 估算：\(Int(recordsBased))s")
            }
            s.status = .abandoned
            s.stopReason = "未正常结束（App 退出 / 强杀）"

            // 顺便用新公式重算 ratio
            var fully = 0.0, wandering = 0.0, distracted = 0.0, idle = 0.0
            for r in s.records {
                switch r.level {
                case .fully: fully += perRecord
                case .wandering: wandering += perRecord
                case .distracted: distracted += perRecord
                case .idle: idle += perRecord
                }
            }
            let observed = max(Double(s.records.count) * perRecord, 1)
            s.fullyRatio = fully / observed
            s.wanderingRatio = wandering / observed
            s.distractedRatio = distracted / observed
            s.idleRatio = idle / observed
        }
        try? ctx.save()
        print("[Reaper] abandoned \(sessions.count) stale running session(s)")
    }

    private static func recalcAllSessionRatios(container: ModelContainer) {
        let ctx = container.mainContext
        let descriptor = FetchDescriptor<FocusSession>()
        guard let sessions = try? ctx.fetch(descriptor) else { return }

        // 历史 session 没存 tickInterval，假设当时也是 5s（项目固定值）
        let perRecord = 5.0
        var migrated = 0
        for s in sessions {
            let records = s.records
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
            migrated += 1
        }
        try? ctx.save()
        print("[Migration] recalc ratios: \(migrated) sessions")
    }
}
