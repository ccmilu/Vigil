import XCTest
@testable import Vigil

/// DistractOverlay 多屏改造的对抗性测试：onClosed 单次语义 + 热插拔重建语义。
///
/// 环境前提：测试宿主是真实 Vigil.app（TEST_HOST），跑在有 window server 的用户会话里，
/// `NSScreen.screens` 非空时 present() 会真实建 panel（屏幕上会闪现遮罩，属正常）。
/// 真无头环境（无屏）下依赖建窗的用例一律 XCTSkip，不退化成假绿。
///
/// 每个用例 tearDown 都复位共享单例：onClosed/onSuppress 置 nil + dismissSilently 清场。
@MainActor
final class DistractOverlayTests: XCTestCase {

    private var overlay: DistractOverlay { DistractOverlay.shared }

    override func tearDown() {
        overlay.onClosed = nil
        overlay.onSuppress = nil
        overlay.dismissSilently()
        super.tearDown()
    }

    // MARK: - 1. dismiss 调两次，onClosed 恰好 fire 一次

    /// 多屏时任一屏点"我回来了"都会进 dismiss()；若实现先 fire 再清字典，
    /// 第二屏按钮的后续回调重入会再 fire 一次（double-fire 打乱 SessionManager cooldown）。
    /// 硬要求：先清空字典再 fire —— 本用例双 dismiss 钉住单次语义。
    func testDismiss_twice_firesOnClosedExactlyOnce() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "无屏环境跳过（R1 后无屏时 present 走零屏路径会 fire 一次 onClosed，干扰本用例计数归因）")
        var count = 0
        overlay.onClosed = { count += 1 }

        overlay.present(reminder: "单次语义测试", promise: "写代码")
        overlay.dismiss()
        overlay.dismiss()

        XCTAssertEqual(count, 1, "dismiss 调两次只应 fire 一次 onClosed（先清字典再 fire）")
    }

    // MARK: - 2. dismissSilently 清场后再 dismiss 不 fire

    /// F2 语义：present() 内部用 dismissSilently() 替换旧遮罩，不触发 onClosed。
    /// 清场后 windows 为空，后续 dismiss 的 wasShown=false 不得 fire。
    func testDismissSilently_thenDismiss_neverFires() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "无屏环境跳过（R1 后无屏时 present 走零屏路径会 fire 一次 onClosed，干扰本用例计数归因）")
        var count = 0
        overlay.onClosed = { count += 1 }

        overlay.present(reminder: "静默关闭测试", promise: "写代码")
        overlay.dismissSilently()
        overlay.dismiss()

        XCTAssertEqual(count, 0, "dismissSilently 清场后 dismiss 不得 fire（wasShown=false）")
    }

    // MARK: - 3. F2：重复 present 不误触旧 onClosed，新闭包恰好 fire 一次

    /// SessionManager 在新一轮 distract 前会把 onClosed 替换为新 cooldown 闭包。
    /// 第二次 present 走 dismissSilently 关旧窗——旧闭包绝不能 fire，
    /// 否则 cooldown 会从"遮罩被替换瞬间"起算而非用户真正关闭时。
    func testRePresent_oldOnClosedNotFired_newFiresOnce() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "无屏环境跳过（R1 后无屏时 present 走零屏路径会 fire 一次 onClosed，干扰本用例计数归因）")
        var oldCount = 0
        var newCount = 0

        overlay.onClosed = { oldCount += 1 }
        overlay.present(reminder: "第一次", promise: "写代码")

        // 模拟 SessionManager.maybeAlertDistraction：替换闭包后再 present
        overlay.onClosed = { newCount += 1 }
        overlay.present(reminder: "第二次", promise: "写代码")

        XCTAssertEqual(oldCount, 0, "重复 present 走 dismissSilently，旧 onClosed 不得被误触")

        overlay.dismiss()
        XCTAssertEqual(oldCount, 0, "旧闭包全程不得 fire")
        XCTAssertEqual(newCount, 1, "新遮罩关闭只应 fire 新闭包恰好一次")
    }

    // MARK: - 4. enabled=false 时 present 直接 return，不建窗不 fire

    /// 注意：本用例恢复 UserDefaults 里的 "overlay.enabled" 原值——它是真实用户设置，
    /// 测试进程宿主是真实 App，改完必须还原。
    func testPresent_whenDisabled_returnsEarlyNoFire() {
        let key = "overlay.enabled"
        let oldValue = UserDefaults.standard.object(forKey: key) as? Bool
        defer {
            if let oldValue {
                UserDefaults.standard.set(oldValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        overlay.enabled = false

        var count = 0
        overlay.onClosed = { count += 1 }
        overlay.present(reminder: "不应出现", promise: "写代码")
        overlay.dismiss()

        XCTAssertEqual(count, 0,
            "enabled=false 时 present 应直接 return 不建窗，dismiss 不得 fire。"
            + "（有屏环境下若未被拦截，用例 1 已证明 dismiss 会 fire）")
    }

    // MARK: - 5. 热插拔重建：不动 onClosed 单次语义（防抖后重建，dismiss 仍恰好 fire 一次）

    /// rebuild 路径只 orderOut 旧窗 + 按 lastPayload 重建，绝不得走 dismiss/dismissSilently
    /// （两者会取消 autoCloseTask / 清 payload / 可能 fire onClosed）。
    /// 重建后 dismiss 恰好 fire 一次 ⟺ 重建保住了 windows 且没碰 onClosed。
    func testScreenChange_rebuildPreservesOnClosedSemantics() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "无屏环境跳过（R1 后无屏时 present 走零屏路径会 fire 一次 onClosed，干扰本用例计数归因）")
        var count = 0
        overlay.onClosed = { count += 1 }

        overlay.present(reminder: "热插拔重建测试", promise: "写代码")
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // 等过 0.3s 合并防抖，让重建完成
        try? await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(count, 0, "热插拔重建期间不得 fire onClosed")

        overlay.dismiss()
        XCTAssertEqual(count, 1, "重建后 dismiss 应正常 fire 恰好一次（windows/lastPayload 被保住）")
    }

    // MARK: - 6. 防抖窗口内 dismiss：防抖到点后的重建不得复活遮罩

    /// present → 立刻来一条屏幕参数变化通知 → 用户在 0.3s 防抖窗口内点掉遮罩。
    /// 防抖到点后 rebuild 必须看到 windows/payload 已清空转而空转；
    /// 若错误复活遮罩，收尾的第二次 dismiss 会再 fire 一次 onClosed（被本断言抓到）。
    func testScreenChange_dismissDuringDebounce_noResurrection() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "无屏环境跳过（R1 后无屏时 present 走零屏路径会 fire，干扰计数归因）")
        var count = 0
        overlay.onClosed = { count += 1 }

        overlay.present(reminder: "防抖竞态测试", promise: "写代码")
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // 防抖窗口（0.3s）内用户关闭遮罩
        overlay.dismiss()
        XCTAssertEqual(count, 1, "正常关闭应 fire 一次")

        try? await Task.sleep(nanoseconds: 600_000_000)  // 让防抖任务到点执行
        overlay.dismiss()  // 若遮罩被重建复活，这次 dismiss 会再 fire
        XCTAssertEqual(count, 1, "dismiss 后防抖重建不得复活遮罩（windows/lastPayload 已清空）")
    }

    // MARK: - 7. R1：零屏收尾补 fire onClosed（生命周期结束语义）

    /// R1 语义：onClosed = 本次提醒生命周期结束（无论真显示了还是没能显示）。
    /// "所有屏取不到 displayID"的零屏路径无法直接驱动（NSScreen 不可 mock，测试宿主必有屏），
    /// 生产侧把零屏收尾抽成 endLifecycleForZeroScreens()——present() 空字典兜底与
    /// 热插拔 rebuild 零屏两处调用点均为一行调用（可审计）。本用例锁定该方法契约：
    /// fire 恰好一次；fire 后状态已清（后续 dismiss / dismissSilently 不得再 fire）。
    func testZeroScreenEndLifecycle_firesOnClosedExactlyOnce() {
        var count = 0
        overlay.onClosed = { count += 1 }

        overlay.endLifecycleForZeroScreens()
        XCTAssertEqual(count, 1,
            "零屏收尾必须 fire 一次 onClosed——SessionManager 靠它把 cooldown 从 distantFuture 拉回")

        // 状态已清：后续任何关闭路径不得二次 fire（恰好一次语义与 dismiss 一致）
        overlay.dismiss()
        overlay.dismissSilently()
        XCTAssertEqual(count, 1, "收尾后再 dismiss / dismissSilently 不得二次 fire")
    }

    /// onClosed 未设置时零屏收尾不得崩（防御锚点）；且收尾幂等不依赖任何窗口存在。
    func testZeroScreenEndLifecycle_nilOnClosed_noCrash() {
        overlay.onClosed = nil
        overlay.endLifecycleForZeroScreens()  // 不崩即通过
    }

    /// R1 语义锚点（无法单测，注释固化）：present() 在"一块屏都没盖上"时调
    /// endLifecycleForZeroScreens() 补 fire onClosed；热插拔 rebuild 后零屏同理。
    /// 若未来有人把这两处调用删掉，SessionManager 的 cooldown 会卡在 distantFuture，
    /// 该段 distract 提醒被永久静默——上述两个用例无法抓到，只能靠 code review。
    /// 详见 DistractOverlay.swift endLifecycleForZeroScreens() 注释。
    func testZeroScreenCallSites_semanticAnchor_documented() {
        // 语义锚点用例：零屏调用点（present 空字典兜底 / rebuild 零屏）无法经 NSScreen 驱动，
        // 此处仅固化"两处调用点必须存在"的约定，NOT_VERIFIED by automation。
        XCTAssertTrue(true, "锚点：present/rebuild 零屏路径必须调 endLifecycleForZeroScreens()")
    }
}
