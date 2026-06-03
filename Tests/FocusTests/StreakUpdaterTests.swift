import XCTest
@testable import Focus

final class StreakUpdaterTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 10))!
    }

    func testFirstActive() {
        let info = StreakInfo()
        StreakUpdater.apply(info: info, now: date(2026, 6, 4), calendar: cal)
        XCTAssertEqual(info.currentStreak, 1)
        XCTAssertEqual(info.longestStreak, 1)
    }

    func testConsecutiveDays() {
        let info = StreakInfo()
        StreakUpdater.apply(info: info, now: date(2026, 6, 4), calendar: cal)
        StreakUpdater.apply(info: info, now: date(2026, 6, 5), calendar: cal)
        StreakUpdater.apply(info: info, now: date(2026, 6, 6), calendar: cal)
        XCTAssertEqual(info.currentStreak, 3)
        XCTAssertEqual(info.longestStreak, 3)
    }

    func testGapResetsCurrent_butKeepsLongest() {
        let info = StreakInfo()
        // 连续 3 天
        StreakUpdater.apply(info: info, now: date(2026, 6, 1), calendar: cal)
        StreakUpdater.apply(info: info, now: date(2026, 6, 2), calendar: cal)
        StreakUpdater.apply(info: info, now: date(2026, 6, 3), calendar: cal)
        XCTAssertEqual(info.longestStreak, 3)
        // 跳过 6/4，6/5 才回来
        StreakUpdater.apply(info: info, now: date(2026, 6, 5), calendar: cal)
        XCTAssertEqual(info.currentStreak, 1)
        XCTAssertEqual(info.longestStreak, 3)  // 历史保留
    }

    func testSameDayIdempotent() {
        let info = StreakInfo()
        StreakUpdater.apply(info: info, now: date(2026, 6, 4), calendar: cal)
        StreakUpdater.apply(info: info, now: date(2026, 6, 4), calendar: cal)
        StreakUpdater.apply(info: info, now: date(2026, 6, 4), calendar: cal)
        XCTAssertEqual(info.currentStreak, 1, "同一天多次 apply 不应叠加")
    }

    func testLongestUpdatesWhenSurpassed() {
        let info = StreakInfo()
        info.longestStreak = 5
        info.currentStreak = 5
        StreakUpdater.apply(info: info, now: date(2026, 6, 4), calendar: cal)
        StreakUpdater.apply(info: info, now: date(2026, 6, 5), calendar: cal)
        // current=5+1=6（因为 lastActive=6/4 然后 +1）；但 lastActive 没初始化
        // 重新构造：
        let info2 = StreakInfo()
        for day in 1...5 {
            StreakUpdater.apply(info: info2, now: date(2026, 6, day), calendar: cal)
        }
        XCTAssertEqual(info2.currentStreak, 5)
        XCTAssertEqual(info2.longestStreak, 5)
        StreakUpdater.apply(info: info2, now: date(2026, 6, 6), calendar: cal)
        XCTAssertEqual(info2.currentStreak, 6)
        XCTAssertEqual(info2.longestStreak, 6)
    }
}
