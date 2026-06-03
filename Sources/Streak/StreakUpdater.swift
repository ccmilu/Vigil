import Foundation
import SwiftData

/// 完成 session 后调一次 update。
/// 规则（按用户本地时区的"日"）：
/// - 本次 actualDuration < 5 分钟 → 不算 active，跳过
/// - lastActive 是今天 → 不变
/// - lastActive 是昨天 → currentStreak += 1，lastActive = today
/// - lastActive 更早 / nil → currentStreak = 1，currentStart = today
/// - 期间维护 longestStreak（含起止日期）
enum StreakUpdater {
    static let minActiveSeconds = 5 * 60

    @MainActor
    static func recordCompletion(
        sessionSeconds: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        in container: ModelContainer
    ) {
        guard sessionSeconds >= minActiveSeconds else { return }
        let ctx = container.mainContext
        let info: StreakInfo
        if let existing = try? ctx.fetch(FetchDescriptor<StreakInfo>()).first {
            info = existing
        } else {
            info = StreakInfo()
            ctx.insert(info)
        }
        apply(info: info, now: now, calendar: calendar)
        try? ctx.save()
    }

    /// 纯函数版本，便于单元测试。直接修改 info 字段。
    static func apply(info: StreakInfo, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let lastDay = info.lastActiveDate.map { calendar.startOfDay(for: $0) }

        if lastDay == today {
            // 今天已经更新过，啥都不做
            return
        }
        if let last = lastDay,
           let diff = calendar.dateComponents([.day], from: last, to: today).day,
           diff == 1 {
            info.currentStreak += 1
        } else {
            info.currentStreak = 1
            info.currentStreakStartDate = today
        }
        info.lastActiveDate = today

        if info.currentStreak > info.longestStreak {
            info.longestStreak = info.currentStreak
            info.longestStreakStartDate = info.currentStreakStartDate
            info.longestStreakEndDate = today
        }
    }
}
