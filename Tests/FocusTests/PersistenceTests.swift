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
}
