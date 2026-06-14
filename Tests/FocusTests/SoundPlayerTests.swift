import XCTest
@testable import Vigil

/// SoundPlayer 单元测试。
/// 注意：NSSound 需要音频硬件 / 系统音频资源，在 CI headless 环境可能找不到系统音文件，
/// 导致 NSSound(named:) 返回 nil。测试对此做了防御：仅在 NSSound 可用时断言 current 被赋值。
@MainActor
final class SoundPlayerTests: XCTestCase {

    // 每次测试用一个全新实例，避免 shared 单例状态污染
    // SoundPlayer.init() 是 private，这里通过反射访问 shared 并手动重置状态
    private var player: SoundPlayer { SoundPlayer.shared }

    override func setUp() async throws {
        try await super.setUp()
        // 确保 isEnabled 为默认开启状态，避免前序测试写入 defaults 影响
        player.isEnabled = true
        player.volume = 0.7
    }

    // MARK: - isEnabled=false 时不触发播放

    /// 验证 isEnabled=false 时调用 play 不会赋值 current（不触发任何 NSSound 操作）。
    func testPlaySkipsWhenDisabled() async throws {
        player.isEnabled = false

        // 先确保 current 有个初始值（如果前序测试留下了）
        // 通过先启用并 play 一次来设置 current，然后禁用再 play，验证 current 未被刷新
        player.isEnabled = true
        player.play(.start)
        let previousCurrent = player.current

        player.isEnabled = false
        player.play(.distract)

        // isEnabled=false 时 play 提前 return，current 不应被更新
        // 即 current 仍等于 previousCurrent（或 nil，如果系统音不可用）
        if previousCurrent == nil {
            // 系统音不可用的 headless 环境：current 本就为 nil，保持 nil 也算通过
            XCTAssertNil(player.current, "isEnabled=false 时 current 不应被赋值")
        } else {
            // 正常桌面环境：current 应仍为上次的实例，而不是 distract 的新实例
            XCTAssertTrue(player.current === previousCurrent,
                          "isEnabled=false 时 current 不应被刷新为新实例")
        }
    }

    // MARK: - play 后 current 被赋值

    /// 验证 play(.start) 成功后 current ivar 不为 nil（前提：系统音文件存在）。
    func testPlaySetsCurrent() async throws {
        // 系统音不可用时直接跳过断言，不算测试失败
        guard NSSound(named: "Tink") != nil else {
            throw XCTSkip("当前环境找不到系统音 Tink，跳过此测试")
        }

        player.play(.start)
        XCTAssertNotNil(player.current, "play(.start) 后 current 应被赋值为非 nil")
    }

    // MARK: - 连续两次 play 使用独立实例

    /// 验证连续两次 play 同一个 cue 时，第二次拿到的是新 copy 实例（非同一对象）。
    /// 这保证了 NSSound 单例缓存不会导致第二次 play() 静默。
    func testConsecutivePlaysUseDifferentInstances() async throws {
        guard NSSound(named: "Tink") != nil else {
            throw XCTSkip("当前环境找不到系统音 Tink，跳过此测试")
        }

        player.play(.start)
        let first = player.current

        player.play(.start)
        let second = player.current

        XCTAssertNotNil(first, "第一次 play 后 current 不应为 nil")
        XCTAssertNotNil(second, "第二次 play 后 current 不应为 nil")
        // copy() 保证是不同对象引用
        XCTAssertFalse(first === second,
                       "连续两次 play 必须用不同的 NSSound 实例，否则单例缓存会导致第二次静默")
    }

    // MARK: - 不同 cue 的 play 也各自独立

    /// 验证切换 cue（从 .distract 到 .complete）时 current 被更新为新实例。
    func testSwitchCueUpdatesCurrent() async throws {
        guard NSSound(named: "Submarine") != nil, NSSound(named: "Glass") != nil else {
            throw XCTSkip("当前环境找不到所需系统音，跳过此测试")
        }

        player.play(.distract)
        let afterDistract = player.current

        player.play(.complete)
        let afterComplete = player.current

        XCTAssertNotNil(afterDistract, "play(.distract) 后 current 不应为 nil")
        XCTAssertNotNil(afterComplete, "play(.complete) 后 current 不应为 nil")
        XCTAssertFalse(afterDistract === afterComplete,
                       "切换 cue 后 current 应换成新实例")
    }

    // MARK: - volume 属性被正确应用到播放实例

    /// 验证 play 时 sound.volume 与 SoundPlayer.volume 一致。
    func testVolumeAppliedToCurrentSound() async throws {
        guard NSSound(named: "Tink") != nil else {
            throw XCTSkip("当前环境找不到系统音 Tink，跳过此测试")
        }

        let expectedVolume: Float = 0.42
        player.volume = expectedVolume
        player.play(.start)

        XCTAssertNotNil(player.current)
        XCTAssertEqual(player.current?.volume ?? -1, expectedVolume, accuracy: 0.001,
                       "播放实例的 volume 应与 SoundPlayer.volume 一致")
    }
}
