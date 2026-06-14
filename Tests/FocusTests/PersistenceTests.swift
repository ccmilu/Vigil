import XCTest
import SwiftData
@testable import Vigil

@MainActor
final class PersistenceTests: XCTestCase {

    func testInsertAndFetchSession() throws {
        let container = AppContainer.inMemory()
        let ctx = container.mainContext

        let s = FocusSession(promise: "写周报", plannedDuration: 1500)
        ctx.insert(s)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.promise, "写周报")
        XCTAssertEqual(all.first?.status, .running)
    }

    func testCascadeDeleteRecords() throws {
        let container = AppContainer.inMemory()
        let ctx = container.mainContext

        let s = FocusSession(promise: "学习", plannedDuration: 1500)
        ctx.insert(s)
        for _ in 0..<3 {
            let r = AnalysisRecord(
                session: s,
                frontAppName: "Safari",
                frontWindowTitles: "Apple Docs",
                level: .fully,
                fromAI: true,
                hasChanged: false
            )
            ctx.insert(r)
        }
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AnalysisRecord>()).count, 3)

        ctx.delete(s)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AnalysisRecord>()).count, 0)
    }

    func testFocusLevelEnumRoundtrip() throws {
        let r = AnalysisRecord(
            frontAppName: "Code",
            frontWindowTitles: "main.swift",
            level: .distracted,
            fromAI: true,
            hasChanged: true
        )
        XCTAssertEqual(r.level, .distracted)
        r.level = .wandering
        XCTAssertEqual(r.levelRaw, "wandering")
    }

    // MARK: - F10 fallback 修复测试

    /// 无效 levelRaw（任意字符串）应 fallback 为 .wandering，而非 .idle
    func testInvalidLevelRawFallbackToWandering() throws {
        let r = AnalysisRecord(
            frontAppName: "Safari",
            frontWindowTitles: "Google",
            level: .fully,
            fromAI: true,
            hasChanged: false
        )
        r.levelRaw = "invalid_value"
        XCTAssertEqual(r.level, .wandering, "无效 rawValue 应 fallback 为 .wandering")
    }

    /// 空字符串 levelRaw 同样应 fallback 为 .wandering
    func testEmptyLevelRawFallbackToWandering() throws {
        let r = AnalysisRecord(
            frontAppName: "Finder",
            frontWindowTitles: "Downloads",
            level: .idle,
            fromAI: false,
            hasChanged: false
        )
        r.levelRaw = ""
        XCTAssertEqual(r.level, .wandering, "空字符串 rawValue 应 fallback 为 .wandering")
    }

    /// 所有合法 FocusLevel case 的 rawValue 均能正确解码
    func testAllValidFocusLevelRawValuesDecodeCorrectly() throws {
        let r = AnalysisRecord(
            frontAppName: "Xcode",
            frontWindowTitles: "Focus.xcodeproj",
            level: .fully,
            fromAI: true,
            hasChanged: false
        )

        r.levelRaw = "fully"
        XCTAssertEqual(r.level, .fully)

        r.levelRaw = "wandering"
        XCTAssertEqual(r.level, .wandering)

        r.levelRaw = "distracted"
        XCTAssertEqual(r.level, .distracted)

        r.levelRaw = "idle"
        XCTAssertEqual(r.level, .idle)
    }

    // MARK: - F12 时钟回拨修复测试

    /// 时钟回拨场景：record.createdAt < session.startedAt
    /// → actualDuration 应降级为 records.count × 5，不能退化为 0
    func testReapStaleSessions_clockSkewBackward_usesRecordsBased() throws {
        let container = AppContainer.inMemory()
        let ctx = container.mainContext

        // 构造一个"未正常结束"的 session，startedAt 比 record 晚（模拟 NTP 回拨）
        let now = Date()
        let startedAt = now  // session 开始时刻
        let session = FocusSession(promise: "测试时钟回拨", plannedDuration: 1800, startedAt: startedAt)
        ctx.insert(session)

        // 插入 120 条 record，createdAt 都比 startedAt 早 60 秒（时钟回拨 60s）
        let skewedTime = now.addingTimeInterval(-60)
        for _ in 0..<120 {
            let r = AnalysisRecord(
                session: session,
                frontAppName: "Xcode",
                frontWindowTitles: "main.swift",
                level: .fully,
                fromAI: true,
                hasChanged: false,
                createdAt: skewedTime
            )
            ctx.insert(r)
        }
        try ctx.save()

        // 调 reapStaleSessions（通过 runAll，ratioRecalcV1 标志位已置 true 时跳过 recalc）
        UserDefaults.standard.set(true, forKey: "migration.ratioRecalc.v1.done")
        Migrations.runAll(container: container)

        // 验证：actualDuration 应为 records.count × 5 = 600s，而非 0
        let sessions = try ctx.fetch(FetchDescriptor<FocusSession>())
        let s = try XCTUnwrap(sessions.first)
        XCTAssertEqual(s.status, .abandoned, "session 应被标记为 abandoned")
        XCTAssertEqual(s.actualDuration, 120 * 5,
            "时钟回拨时 actualDuration 应降级为 records.count × 5 = \(120 * 5)s，而非 0")
        XCTAssertGreaterThan(s.actualDuration, 0, "actualDuration 不能退化为 0")
    }

    /// 正常路径：record.createdAt > session.startedAt，wall-clock 差合理
    /// → actualDuration 应接近 wall-clock 差
    func testReapStaleSessions_normalPath_usesWallClock() throws {
        let container = AppContainer.inMemory()
        let ctx = container.mainContext

        let now = Date()
        let startedAt = now.addingTimeInterval(-600)  // 10 分钟前开始
        let session = FocusSession(promise: "正常专注 10 分钟", plannedDuration: 1800, startedAt: startedAt)
        ctx.insert(session)

        // 插入 record，createdAt 在 startedAt 之后（正常情况）
        let lastRecordTime = now.addingTimeInterval(-5)  // 最后一帧在 5 秒前
        for i in 0..<10 {
            let recordTime = startedAt.addingTimeInterval(Double(i) * 5 + 5)
            let r = AnalysisRecord(
                session: session,
                frontAppName: "Xcode",
                frontWindowTitles: "main.swift",
                level: .fully,
                fromAI: true,
                hasChanged: false,
                createdAt: i == 9 ? lastRecordTime : recordTime
            )
            ctx.insert(r)
        }
        try ctx.save()

        UserDefaults.standard.set(true, forKey: "migration.ratioRecalc.v1.done")
        Migrations.runAll(container: container)

        let sessions = try ctx.fetch(FetchDescriptor<FocusSession>())
        let s = try XCTUnwrap(sessions.first)
        XCTAssertEqual(s.status, .abandoned)

        // wall-clock 差 ≈ lastRecordTime - startedAt ≈ 595s，应使用 wall-clock 而非 records×5=50s
        let expectedWallClock = Int(lastRecordTime.timeIntervalSince(startedAt))
        XCTAssertEqual(s.actualDuration, expectedWallClock,
            "正常路径 actualDuration 应等于 wall-clock 差（\(expectedWallClock)s）")
        XCTAssertGreaterThan(s.actualDuration, 10 * 5,
            "wall-clock 差（\(expectedWallClock)s）应大于 records×5（\(10 * 5)s）")
    }
}
