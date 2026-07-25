import XCTest
@testable import Vigil

/// MultiDisplayDHash 纯逻辑测试：Data 字典进出，无 CGImage 依赖。
/// 语义约定见 Sources/Capture/DHashComputer.swift 的 enum 注释。
final class MultiDisplayDHashTests: XCTestCase {

    // 测试用 displayID（UInt32 字面量即 CGDirectDisplayID；编号 1<2<3 也用于验证并列时小编号胜出）
    private let disp1: CGDirectDisplayID = 1
    private let disp2: CGDirectDisplayID = 2
    private let disp3: CGDirectDisplayID = 3

    // 两个极端哈希：全 0 与全 1 → 汉明距离 = 256（256-bit 满距离）；相同则距离 0
    private let zeros = Data(repeating: 0x00, count: 32)
    private let ones  = Data(repeating: 0xFF, count: 32)

    // MARK: - old == nil → firstFrame 语义

    /// old=nil 时 new 中每屏都记 Int.max（全新画面必触发分析，绝不可能被当 distance=0 跳过）
    func testNilOld_allNewDisplaysAreIntMax() {
        let r = MultiDisplayDHash.distances(old: nil, new: [disp1: zeros, disp2: ones])
        XCTAssertEqual(r.perDisplay.count, 2)
        XCTAssertEqual(r.perDisplay[disp1], Int.max)
        XCTAssertEqual(r.perDisplay[disp2], Int.max)
        XCTAssertEqual(r.max, Int.max)
        // 全部并列 Int.max → 小编号屏胜出（确定性）
        XCTAssertEqual(r.maxDisplayID, disp1)
    }

    // MARK: - 双屏均稳 → max 距离为 0（FrameAnalyzer 据此 skip）

    func testBothDisplaysStable_maxIsZero() {
        let old: [CGDirectDisplayID: Data] = [disp1: zeros, disp2: ones]
        let new: [CGDirectDisplayID: Data] = [disp1: zeros, disp2: ones]
        let r = MultiDisplayDHash.distances(old: old, new: new)
        XCTAssertEqual(r.perDisplay[disp1], 0)
        XCTAssertEqual(r.perDisplay[disp2], 0)
        XCTAssertEqual(r.max, 0)
        // 距离 0 也要给出 maxDisplayID（落库 dhashHex 需要取该屏哈希）
        XCTAssertEqual(r.maxDisplayID, disp1)
    }

    // MARK: - 一屏剧变 → max 选中该屏

    func testOneDisplayChangesDrastically_maxPicksThatDisplay() {
        let old: [CGDirectDisplayID: Data] = [disp1: zeros, disp2: zeros]
        let new: [CGDirectDisplayID: Data] = [disp1: zeros, disp2: ones]  // 仅屏 2 全变
        let r = MultiDisplayDHash.distances(old: old, new: new)
        XCTAssertEqual(r.perDisplay[disp1], 0)
        XCTAssertEqual(r.perDisplay[disp2], 256)
        XCTAssertEqual(r.max, 256)
        XCTAssertEqual(r.maxDisplayID, disp2, "max 应选中剧变的那块屏")
    }

    // MARK: - 热插入新屏 → 该屏记 Int.max，必触发分析

    func testNewlyAttachedDisplay_isIntMax() {
        let old: [CGDirectDisplayID: Data] = [disp1: zeros]
        let new: [CGDirectDisplayID: Data] = [disp1: zeros, disp2: zeros]  // 屏 2 是新插入的
        let r = MultiDisplayDHash.distances(old: old, new: new)
        XCTAssertEqual(r.perDisplay[disp1], 0)
        XCTAssertEqual(r.perDisplay[disp2], Int.max, "old 无记录的屏应记 Int.max")
        XCTAssertEqual(r.max, Int.max)
        XCTAssertEqual(r.maxDisplayID, disp2)
    }

    // MARK: - 旧屏被拔除 → 只对 new 中现存屏求值

    func testRemovedDisplay_notEvaluated() {
        // old 里屏 2 与现存屏 1 哈希完全相反；若被错误纳入求值会把 max 拉到 256
        let old: [CGDirectDisplayID: Data] = [disp1: zeros, disp2: ones, disp3: ones]
        let new: [CGDirectDisplayID: Data] = [disp1: zeros]  // 屏 2/3 已拔除
        let r = MultiDisplayDHash.distances(old: old, new: new)
        XCTAssertEqual(r.perDisplay.count, 1, "只评 new 中存在的屏")
        XCTAssertNil(r.perDisplay[disp2])
        XCTAssertNil(r.perDisplay[disp3])
        XCTAssertEqual(r.max, 0, "已拔除屏的旧哈希不得影响 max")
        XCTAssertEqual(r.maxDisplayID, disp1)
    }

    // MARK: - 空 new 字典边界

    func testEmptyNew_returnsZeroMaxAndNilID() {
        let r1 = MultiDisplayDHash.distances(old: [disp1: zeros], new: [:])
        XCTAssertTrue(r1.perDisplay.isEmpty)
        XCTAssertEqual(r1.max, 0)
        XCTAssertNil(r1.maxDisplayID)

        // old=nil + 空 new 同样安全
        let r2 = MultiDisplayDHash.distances(old: nil, new: [:])
        XCTAssertTrue(r2.perDisplay.isEmpty)
        XCTAssertEqual(r2.max, 0)
        XCTAssertNil(r2.maxDisplayID)
    }

    // MARK: - 并列距离 → 小编号屏胜出（结果确定性）

    func testTiedDistances_smallerDisplayIDWins() {
        let old: [CGDirectDisplayID: Data] = [disp1: zeros, disp2: zeros]
        let new: [CGDirectDisplayID: Data] = [disp1: ones, disp2: ones]  // 双屏同距 256
        let r = MultiDisplayDHash.distances(old: old, new: new)
        XCTAssertEqual(r.max, 256)
        XCTAssertEqual(r.maxDisplayID, disp1, "并列时应确定性地选小编号屏")
    }
}
