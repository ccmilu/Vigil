import XCTest
import SwiftData
@testable import Vigil

@MainActor
final class PlayTimerSeedTests: XCTestCase {

    // MARK: - 辅助

    /// 每个 test case 都用独立的 in-memory container，避免状态污染。
    private func makeContainer() -> ModelContainer {
        AppContainer.inMemory()
    }

    private func fetchTimers(_ container: ModelContainer) throws -> [PlayTimer] {
        try container.mainContext.fetch(
            FetchDescriptor<PlayTimer>(sortBy: [SortDescriptor(\.slot)])
        )
    }

    // MARK: - 测试：首次 seed 插入 5 条

    func testSeedDefaultPlayTimers_insertsDefaultPresets() throws {
        let container = makeContainer()

        Migrations.seedDefaultPlayTimers(container: container)

        let timers = try fetchTimers(container)
        XCTAssertEqual(timers.count, 5, "首次 seed 应插入 5 条默认预设")

        // 验证 seconds 与 slot
        let expectedSeconds = [600, 900, 1500, 2700, 3600]
        for (index, timer) in timers.enumerated() {
            XCTAssertEqual(timer.seconds, expectedSeconds[index],
                "slot \(index) 的 seconds 应为 \(expectedSeconds[index])，实际：\(timer.seconds)")
            XCTAssertEqual(timer.slot, index,
                "第 \(index) 条的 slot 应为 \(index)，实际：\(timer.slot)")
        }
    }

    // MARK: - 测试：重复调用幂等（仍 5 条）

    func testSeedDefaultPlayTimers_idempotent_onEmptyTable() throws {
        let container = makeContainer()

        // 第一次
        Migrations.seedDefaultPlayTimers(container: container)
        // 第二次
        Migrations.seedDefaultPlayTimers(container: container)

        let timers = try fetchTimers(container)
        XCTAssertEqual(timers.count, 5, "重复 seed 应保持幂等，仍为 5 条")
    }

    // MARK: - 测试：表非空时跳过（保护用户自定义数据）

    func testSeedDefaultPlayTimers_skipsWhenTableNotEmpty() throws {
        let container = makeContainer()
        let ctx = container.mainContext

        // 手动插入 1 条自定义 PlayTimer
        let custom = PlayTimer(seconds: 1234, slot: 0)
        ctx.insert(custom)
        try ctx.save()

        // 调用 seed，应跳过
        Migrations.seedDefaultPlayTimers(container: container)

        let timers = try fetchTimers(container)
        XCTAssertEqual(timers.count, 1, "表非空时 seed 应跳过，不新增任何条目")
        XCTAssertEqual(timers.first?.seconds, 1234, "已有数据不应被覆盖")
    }

    // MARK: - 测试：通过 runAll 触发 seed（UserDefaults key 控制）

    func testRunAll_seedsPlayTimersOnFirstRun() throws {
        let container = makeContainer()

        // 清除 UserDefaults 相关 key，模拟首次启动
        UserDefaults.standard.removeObject(forKey: "migration.ratioRecalc.v1.done")
        UserDefaults.standard.removeObject(forKey: "migration.seedDefaultPlayTimers.v1.done")

        Migrations.runAll(container: container)

        let timers = try fetchTimers(container)
        XCTAssertEqual(timers.count, 5, "runAll 首次执行后应 seed 5 条 PlayTimer")

        // 恢复标志位，避免影响其他测试
        UserDefaults.standard.set(true, forKey: "migration.ratioRecalc.v1.done")
        UserDefaults.standard.set(true, forKey: "migration.seedDefaultPlayTimers.v1.done")
    }
}
