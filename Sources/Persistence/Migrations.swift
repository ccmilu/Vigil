import Foundation
import SwiftData

/// 一次性数据迁移。每次新增迁移加一个 UserDefaults 标志位，run 完置 true。
@MainActor
enum Migrations {
    /// v1：把所有历史 session 的 4 个 ratio 用新公式（分母 = records 数 × 5s）重算。
    /// 旧公式分母用 actualDuration，导致 .skippedNoWindows 等不入库的 tick 让总和 < 100%，
    /// 柱状图右边出现空白。
    private static let key_ratioRecalcV1 = "migration.ratioRecalc.v1.done"

    static func runAll(container: ModelContainer) {
        // 一次性数据迁移
        if !UserDefaults.standard.bool(forKey: key_ratioRecalcV1) {
            recalcAllSessionRatios(container: container)
            UserDefaults.standard.set(true, forKey: key_ratioRecalcV1)
        }
        // 每次启动跑：回收上次没正常结束的僵尸 session
        reapStaleSessions(container: container)
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
            s.actualDuration = max(Int(lastTime.timeIntervalSince(s.startedAt)), 0)
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
