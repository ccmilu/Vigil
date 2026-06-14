import XCTest
import SwiftData
@testable import Vigil

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

    // MARK: - F4 跨 session 状态隔离测试

    /// F4 验证：第一个 session 内人工把 distract 提醒状态设为残留值，
    /// endSession 后这 8 个字段都应被 resetPerSessionAlertState() 清空，
    /// 下一个 session 开始时状态干净（不会静默掉首次 distract 提醒）。
    func testEndSession_clearsAllPerSessionAlertState() async throws {
        let container = AppContainer.inMemory()
        let mock = MockAIService(level: .fully)
        let mgr = FocusSessionManager(
            modelContainer: container,
            service: mock
        )

        // 第一个 session：起 + 人为注入残留状态
        _ = await mgr.start(promise: "写代码", durationSeconds: 60)
        mgr.distractCooldownUntil = .distantFuture   // 模拟遮罩弹出期间的 cooldown 锁
        mgr.distractSuppressedInStreak = true          // 模拟用户点过"不再提醒"
        mgr.distractAlertCount = 5
        mgr.lastDistractReminder = "你在玩手机"
        mgr.idleStreakStartedAt = Date()
        mgr.idleNextSoundAt = Date().addingTimeInterval(30)
        mgr.wanderingStreakStartedAt = Date()
        mgr.wanderingNextAlertAt = Date().addingTimeInterval(60)

        // 结束第一个 session
        await mgr.stopManually(reason: "F4 测试")

        // endSession 应已通过 resetPerSessionAlertState() 清空所有字段
        XCTAssertNil(mgr.distractCooldownUntil,        "distractCooldownUntil 应被清为 nil")
        XCTAssertFalse(mgr.distractSuppressedInStreak, "distractSuppressedInStreak 应被重置为 false")
        XCTAssertEqual(mgr.distractAlertCount, 0,      "distractAlertCount 应归零")
        XCTAssertEqual(mgr.lastDistractReminder, "",   "lastDistractReminder 应被清空")
        XCTAssertNil(mgr.idleStreakStartedAt,           "idleStreakStartedAt 应被清为 nil")
        XCTAssertNil(mgr.idleNextSoundAt,               "idleNextSoundAt 应被清为 nil")
        XCTAssertNil(mgr.wanderingStreakStartedAt,      "wanderingStreakStartedAt 应被清为 nil")
        XCTAssertNil(mgr.wanderingNextAlertAt,          "wanderingNextAlertAt 应被清为 nil")
    }

    // MARK: - F11 convenience init 使用 AppSettings.shared 测试

    /// F11 验证：通过 convenience init 创建的 manager，
    /// 其内部 settings 与 AppSettings.shared 是同一个实例（引用相同）。
    func testConvenienceInit_usesSingletonSettings() {
        let container = AppContainer.inMemory()
        let mock = MockAIService(level: .fully)
        let mgr = FocusSessionManager(
            modelContainer: container,
            service: mock
        )

        // 通过改动 AppSettings.shared 的一个值，观察 mgr 读出的是否与 shared 一致。
        // 由于 @AppStorage 每次读 UserDefaults，只要 mgr.settings 指向 shared，
        // 二者 dhashThreshold 会同步。此处直接对比对象引用：convenience init 内
        // 硬编码了 AppSettings.shared，所以 mgr.settings === AppSettings.shared。
        // （settings 字段 internal 可在 @testable import 下访问）
        XCTAssertTrue(mgr.settings === AppSettings.shared,
                      "convenience init 应使用 AppSettings.shared 而非新建独立实例")
    }
}

// FocusSessionManager.Phase 已经在主 target 标 Equatable，这里不需要再实现
