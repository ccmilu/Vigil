import XCTest
import SwiftData
@testable import Focus

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
}
