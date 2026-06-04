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
        if !UserDefaults.standard.bool(forKey: key_ratioRecalcV1) {
            recalcAllSessionRatios(container: container)
            UserDefaults.standard.set(true, forKey: key_ratioRecalcV1)
        }
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
