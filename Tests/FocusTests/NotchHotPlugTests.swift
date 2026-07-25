import XCTest
@testable import Vigil

/// NotchTimer / NotchIslandController 多屏改造的热插拔对抗性测试。
///
/// 环境前提：TEST_HOST 是真实 Vigil.app、跑在有 window server 的会话里。
/// show() 会在用户真实屏幕上短暂显示刘海岛并注册鼠标 monitor + 轮询 Timer，
/// 每个用例 setUp/tearDown 都 hide() 复位共享单例（配对释放路径本身也是被测对象）。
/// 无屏环境下依赖建 controller 的用例一律 XCTSkip，不退化成假绿。
@MainActor
final class NotchHotPlugTests: XCTestCase {

    private var timer: NotchTimer { NotchTimer.shared }

    override func setUp() {
        super.setUp()
        // 每个用例从干净状态开始：全部 teardown + 清空
        timer.hide()
    }

    override func tearDown() {
        timer.hide()
        super.tearDown()
    }

    private func postScreenChange() {
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// 当前全部 controller 的实例标识——重建后应整批换成新实例
    private func controllerIDs() -> Set<ObjectIdentifier> {
        Set(timer.controllers.values.map { ObjectIdentifier($0) })
    }

    // MARK: - 1. controllers 为空时热插拔通知空转：不崩、不建 controller

    /// 未在显示（hide 后 / 从未 show）时收到屏幕参数变化，rebuild 必须 guard 空转——
    /// 否则用户在非会话状态插拔显示器会凭空冒出刘海岛。
    func testScreenChange_withEmptyControllers_noOp() async {
        XCTAssertTrue(timer.controllers.isEmpty, "前置：hide 后 controllers 应为空")

        postScreenChange()
        try? await Task.sleep(nanoseconds: 600_000_000)  // 等过 0.3s 防抖

        XCTAssertTrue(timer.controllers.isEmpty,
                      "未显示岛时热插拔不得凭空建 controller")
    }

    // MARK: - 2. 防抖合并：连续多条通知只在最后一条的 0.3s 后重建一次

    /// 一次真实插拔 / 改分辨率会连发多条通知。若防抖失效（每条各重建一次），
    /// 第一条通知 +0.3s 就会重建——"最后一条 +0.15s 时实例仍未变"这个检查点会抓到。
    /// 时序设计：检查点宁可灵敏度低，不可因调度抖动 false fail：
    /// - Task.sleep 只会晚不会早，重建最早发生在最后一条通知 +0.3s
    /// - "未重建"检查点在最后一条 +0.15s（实际睡眠拖到 +0.2s 也仍 < 0.3s，安全）
    /// - "已重建"检查点在最后一条 +0.75s（给 MainActor hop + 调度留 0.45s 余量）
    func testScreenChange_debounceCoalescesRapidNotifications() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "无屏环境跳过（show 建不了 controller）")
        timer.show(promise: "防抖测试", plannedSeconds: 1500)
        XCTAssertFalse(timer.controllers.isEmpty, "前置：show 后应有 controller")
        let before = controllerIDs()

        postScreenChange()
        try? await Task.sleep(nanoseconds: 100_000_000)
        postScreenChange()
        try? await Task.sleep(nanoseconds: 100_000_000)
        postScreenChange()

        // 最后一条通知后 0.15s：防抖窗口未到期，不得重建
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(controllerIDs(), before,
                       "防抖窗口内不得重建（连续通知应合并为最后一次的 0.3s）")

        // 最后一条通知后累计约 0.75s：防抖已过，应已整批重建为新实例
        try? await Task.sleep(nanoseconds: 600_000_000)
        let after = controllerIDs()
        XCTAssertEqual(after.count, before.count, "重建后岛数量应与屏幕数一致")
        XCTAssertFalse(after.isEmpty)
        XCTAssertTrue(after.isDisjoint(with: before),
                      "防抖到期后应整批重建为全新 controller 实例")
    }

    // MARK: - 3. 防抖窗口内 hide()：防抖到点后的重建不得复活岛

    /// show → 立刻来一条通知 → 0.3s 防抖窗口内 session 结束触发 hide()。
    /// 防抖到点后 rebuild 的 `guard !controllers.isEmpty` 必须空转，
    /// 否则已结束的会话会在屏幕上复活一座孤岛。
    func testScreenChange_hideDuringDebounce_doesNotResurrect() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "无屏环境跳过")
        timer.show(promise: "hide 竞态测试", plannedSeconds: 1500)
        XCTAssertFalse(timer.controllers.isEmpty, "前置：show 后应有 controller")

        postScreenChange()
        timer.hide()  // 防抖窗口内隐藏
        try? await Task.sleep(nanoseconds: 600_000_000)  // 让防抖任务到点执行

        XCTAssertTrue(timer.controllers.isEmpty,
                      "hide 后防抖重建不得复活 controller（guard 空转）")
    }

    // MARK: - 4. 重复 show() 复用既有 controller（不重建实例 → 不累积 monitor/Timer）

    /// monitor 与轮询 Timer 都在 createWindow() 里注册；若重复 show 重建实例而不 teardown
    /// 旧的，NSEvent monitor / Timer 会随调用次数累积泄漏。
    /// 实例集合不变 ⟺ syncControllers 幂等 + createWindow 只在 window==nil 时跑。
    func testShow_twiceWithoutHide_reusesSameControllers() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "无屏环境跳过")
        timer.show(promise: "重复 show 测试", plannedSeconds: 1500)
        let first = controllerIDs()
        XCTAssertFalse(first.isEmpty, "前置：show 后应有 controller")

        timer.show(promise: "重复 show 测试", plannedSeconds: 1500)

        XCTAssertEqual(controllerIDs(), first,
                       "重复 show 不得重建 controller 实例（否则旧 monitor/Timer 泄漏）")
    }

    // MARK: - 5. hovering 兼容壳：无 controller 时写入静默丢弃、读取恒 false

    /// NotchTimer.hovering 是主屏 controller 的代理壳；测试环境未 show() 时
    /// 旧调用方（如 NotchGeometryTests）写 hovering 不得崩、不得残留脏状态。
    func testHoveringProxy_withoutControllers_writeDropped() {
        XCTAssertTrue(timer.controllers.isEmpty, "前置：无 controller")

        timer.hovering = true

        XCTAssertFalse(timer.hovering, "无 controller 时 hovering 写入应被静默丢弃、读取恒 false")
    }
}
