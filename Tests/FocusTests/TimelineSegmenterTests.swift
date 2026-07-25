import XCTest
@testable import Vigil

/// 时间轴分段合并逻辑：dHash 复用 / 空闲等无信息增量帧并入前一段，
/// AI 帧 / 有截图的超时回落帧 / level 变化帧保持独立段。
final class TimelineSegmenterTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func rec(
        level: FocusLevel,
        fromAI: Bool,
        hasScreenshot: Bool = false,
        atSec: TimeInterval
    ) -> AnalysisRecord {
        AnalysisRecord(
            screenshotLocalPath: hasScreenshot ? "sid/x.jpg" : nil,
            frontAppName: "Xcode",
            frontWindowTitles: "",
            level: level,
            reasoning: fromAI ? "用户在写代码" : "",
            fromAI: fromAI,
            hasChanged: fromAI,
            createdAt: t0.addingTimeInterval(atSec)
        )
    }

    func testReuseFramesMergeIntoPreviousAISegment() {
        let records = [
            rec(level: .fully, fromAI: true, hasScreenshot: true, atSec: 0),
            rec(level: .fully, fromAI: false, atSec: 5),
            rec(level: .fully, fromAI: false, atSec: 10),
            rec(level: .fully, fromAI: false, atSec: 15),
        ]
        let segs = TimelineSegmenter.makeSegments(from: records)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].count, 4)
        XCTAssertEqual(segs[0].first.createdAt, t0)
        XCTAssertEqual(segs[0].last.createdAt, t0.addingTimeInterval(15))
    }

    func testLevelChangeStartsNewSegment() {
        let records = [
            rec(level: .fully, fromAI: true, hasScreenshot: true, atSec: 0),
            rec(level: .fully, fromAI: false, atSec: 5),
            rec(level: .distracted, fromAI: true, hasScreenshot: true, atSec: 10),
            rec(level: .distracted, fromAI: false, atSec: 15),
        ]
        let segs = TimelineSegmenter.makeSegments(from: records)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].count, 2)
        XCTAssertEqual(segs[1].count, 2)
        XCTAssertEqual(segs[1].first.level, .distracted)
    }

    func testConsecutiveIdleFramesMerge() {
        let records = [
            rec(level: .fully, fromAI: true, hasScreenshot: true, atSec: 0),
            rec(level: .idle, fromAI: false, atSec: 5),
            rec(level: .idle, fromAI: false, atSec: 10),
            rec(level: .idle, fromAI: false, atSec: 15),
        ]
        let segs = TimelineSegmenter.makeSegments(from: records)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[1].count, 3)
        XCTAssertEqual(segs[1].first.level, .idle)
    }

    func testTimeoutFallbackWithScreenshotKeepsOwnSegment() {
        // AI 超时回落帧 fromAI=false 但有截图（画面确实变了），不合并
        let records = [
            rec(level: .fully, fromAI: true, hasScreenshot: true, atSec: 0),
            rec(level: .fully, fromAI: false, hasScreenshot: true, atSec: 5),
        ]
        let segs = TimelineSegmenter.makeSegments(from: records)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[1].count, 1)
    }

    func testLeadingReuseFrameFormsOwnSegment() {
        // 边界：首帧就是复用帧（没有可并入的前段）→ 自成一段
        let records = [
            rec(level: .wandering, fromAI: false, atSec: 0),
            rec(level: .wandering, fromAI: false, atSec: 5),
        ]
        let segs = TimelineSegmenter.makeSegments(from: records)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].count, 2)
    }

    func testAIFrameAfterReuseStartsNewSegment() {
        // 每个 AI 帧都是新锚点，即使 level 与上一段相同（有新推理文本）
        let records = [
            rec(level: .fully, fromAI: true, hasScreenshot: true, atSec: 0),
            rec(level: .fully, fromAI: false, atSec: 5),
            rec(level: .fully, fromAI: true, hasScreenshot: true, atSec: 10),
        ]
        let segs = TimelineSegmenter.makeSegments(from: records)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].count, 2)
        XCTAssertEqual(segs[1].count, 1)
    }
}
