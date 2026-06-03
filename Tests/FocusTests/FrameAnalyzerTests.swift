import XCTest
import CoreGraphics
@testable import Focus

final class FrameAnalyzerTests: XCTestCase {

    func testFirstFrameTriggersAI_andSecondSameFrameSkips() async throws {
        let img = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: false)
        let mock = MockAIService(level: .fully)
        let analyzer = makeAnalyzer(service: mock)

        // 第一帧 → analyzed (firstFrame)
        let r1 = await analyzer.tick(captureOverride: { img })
        if case .analyzed(let reason, let dist, let level, let fromAI) = r1.decision {
            XCTAssertEqual(reason, .firstFrame)
            XCTAssertNil(dist)
            XCTAssertEqual(level, .fully)
            XCTAssertTrue(fromAI)
        } else {
            XCTFail("第一帧应被分析；实际 \(r1.decision)")
        }

        // 第二帧（同图）→ skippedDhashStable
        let r2 = await analyzer.tick(captureOverride: { img })
        if case .skippedDhashStable(let dist) = r2.decision {
            XCTAssertLessThan(dist, 30)
        } else {
            XCTFail("同图应 skip；实际 \(r2.decision)")
        }
    }

    func testChangedImageTriggersAI() async throws {
        let a = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: false)
        let b = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: true)
        let mock = MockAIService(level: .distracted)
        let analyzer = makeAnalyzer(service: mock)

        _ = await analyzer.tick(captureOverride: { a })
        let r = await analyzer.tick(captureOverride: { b })
        if case .analyzed(let reason, let dist, let level, _) = r.decision {
            XCTAssertEqual(reason, .dhashChanged)
            XCTAssertGreaterThanOrEqual(dist ?? 0, 30)
            XCTAssertEqual(level, .distracted)
        } else {
            XCTFail("反色图应被分析；实际 \(r.decision)")
        }
    }

    func testAIFailureFallbackKeepsLastLevel() async throws {
        let img = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: false)
        let mock = MockAIService(level: .fully)
        let analyzer = makeAnalyzer(service: mock)

        // 先成功一次建立 lastLevel
        _ = await analyzer.tick(captureOverride: { img })

        // 切到失败模式，喂个不同图
        await mock.setShouldFail(true)
        let b = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: true)
        let r = await analyzer.tick(captureOverride: { b })
        if case .analyzed(_, _, let level, let fromAI) = r.decision {
            XCTAssertEqual(level, .fully, "AI 失败应回落到 lastLevel")
            XCTAssertFalse(fromAI, "fromAI 应为 false（失败兜底）")
        } else {
            XCTFail("应仍走 analyzed 分支；实际 \(r.decision)")
        }
    }

    func testNoWindowsCausesSkip() async throws {
        let mock = MockAIService(level: .fully)
        let analyzer = makeAnalyzer(service: mock)
        let r = await analyzer.tick(captureOverride: {
            throw ScreenCaptureManager.CaptureError.desktopOnly
        })
        XCTAssertEqual(r.decision, .skippedNoWindows)
    }

    // MARK: - Helpers

    private func makeAnalyzer(service: AIService) -> FrameAnalyzer {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus_test_\(UUID().uuidString).jsonl")
        var cfg = CaptureConfig()
        cfg.idleThreshold = 9_999_999  // 测试中禁用 idle 闸门
        return FrameAnalyzer(
            service: service,
            config: cfg,
            sessionID: UUID(),
            promise: "写周报",
            diagnosticLogURL: logURL
        )
    }
}

actor MockAIService: AIService {
    private var level: FocusLevel
    private var shouldFail = false

    init(level: FocusLevel) { self.level = level }
    func setShouldFail(_ v: Bool) { shouldFail = v }
    func setLevel(_ l: FocusLevel) { level = l }

    func analyzeTask(_ promise: String) async throws -> TaskAnalysis {
        TaskAnalysis(taskType: .other, suggestion: nil)
    }

    func analyzeFrame(_ input: FrameAnalysisInput) async throws -> FrameAnalysis {
        if shouldFail {
            throw AIServiceError.network(URLError(.timedOut))
        }
        return FrameAnalysis(level: level, reasoning: "mock", reminder: "")
    }

    func summarize(_ input: SummaryInput) async throws -> String {
        "mock summary"
    }
}
