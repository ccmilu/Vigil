import XCTest
import SwiftData
@testable import Focus

@MainActor
final class SessionManagerTests: XCTestCase {

    func testStartTransitionsToRunning_andStopToCompleted() async throws {
        let container = AppContainer.inMemory()
        let mock = MockAIService(level: .fully)
        let mgr = FocusSessionManager(
            modelContainer: container,
            service: mock
        )
        XCTAssertEqual(mgr.phase, .idle)

        let result = await mgr.start(promise: "写周报", durationSeconds: 60)
        if case .success(let id) = result {
            // start 完应处于 running
            if case .running(let p, _) = mgr.phase {
                XCTAssertEqual(p, "写周报")
            } else {
                XCTFail("应处于 running；实际 \(mgr.phase)")
            }
            // 数据库里应能查到
            let all = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
            XCTAssertTrue(all.contains(where: { $0.id == id }))
        } else {
            XCTFail("start 失败")
        }

        await mgr.stopManually(reason: "手动测试")
        if case .completed = mgr.phase {
            // ok
        } else {
            XCTFail("应处于 completed；实际 \(mgr.phase)")
        }

        // 检查 session 已落盘 actualDuration/summary
        let s = try container.mainContext.fetch(FetchDescriptor<FocusSession>()).first!
        XCTAssertEqual(s.status, .manualCompleted)
        XCTAssertEqual(s.stopReason, "手动测试")
        XCTAssertNotNil(s.summary)  // mock 返回 "mock summary"
    }
}

extension FocusSessionManager.Phase: @retroactive Equatable {
    public static func == (lhs: FocusSessionManager.Phase, rhs: FocusSessionManager.Phase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.preparing(let a), .preparing(let b)): return a == b
        case (.running(let pa, _), .running(let pb, _)): return pa == pb
        case (.analyzing, .analyzing): return true
        case (.completed, .completed): return true
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}
