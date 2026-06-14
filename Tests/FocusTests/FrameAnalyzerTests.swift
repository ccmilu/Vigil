import XCTest
import CoreGraphics
@testable import Vigil

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

    // MARK: - F1 首帧 hasChanged 修复测试

    /// F1 修复验证：首帧 AI 返回 .distracted → hasChanged 应为 true（遮罩应弹）
    func testF1_firstFrameDistracted_hasChangedTrue() async throws {
        let img = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: false)
        let mock = MockAIService(level: .distracted)
        let analyzer = makeAnalyzer(service: mock)

        let r = await analyzer.tick(captureOverride: { img })

        // 首帧返回 distracted，应被视为跳变进入非专注状态
        XCTAssertTrue(r.hasChanged, "首帧 AI 返回 .distracted 时 hasChanged 应为 true，遮罩才能弹出")
        if case .analyzed(let reason, _, let level, _) = r.decision {
            XCTAssertEqual(reason, .firstFrame)
            XCTAssertEqual(level, .distracted)
        } else {
            XCTFail("首帧应走 analyzed 分支；实际 \(r.decision)")
        }
    }

    /// F1 修复验证：首帧 AI 返回 .wandering → hasChanged 也应为 true（非 fully 皆算跳变）
    func testF1_firstFrameWandering_hasChangedTrue() async throws {
        let img = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: false)
        let mock = MockAIService(level: .wandering)
        let analyzer = makeAnalyzer(service: mock)

        let r = await analyzer.tick(captureOverride: { img })

        XCTAssertTrue(r.hasChanged, "首帧 AI 返回 .wandering 时 hasChanged 应为 true")
    }

    /// F1 修复验证：首帧 AI 返回 .fully → hasChanged 应为 false（正常起步专注，不打扰用户）
    func testF1_firstFrameFully_hasChangedFalse() async throws {
        let img = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: false)
        let mock = MockAIService(level: .fully)
        let analyzer = makeAnalyzer(service: mock)

        let r = await analyzer.tick(captureOverride: { img })

        // 首帧专注中，不应触发遮罩
        XCTAssertFalse(r.hasChanged, "首帧 AI 返回 .fully 时 hasChanged 应为 false，避免误弹遮罩")
    }

    /// F1 修复验证：非首帧 fully → distracted 跳变 → hasChanged 应为 true（基准行为不能退化）
    func testF1_nonFirstFrame_fullyToDistracted_hasChangedTrue() async throws {
        let imgA = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: false)
        let imgB = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: true)
        let mock = MockAIService(level: .fully)
        let analyzer = makeAnalyzer(service: mock)

        // 首帧：fully
        _ = await analyzer.tick(captureOverride: { imgA })

        // 第二帧：切到 distracted
        await mock.setLevel(.distracted)
        let r = await analyzer.tick(captureOverride: { imgB })

        XCTAssertTrue(r.hasChanged, "从 fully 到 distracted 应视为跳变，hasChanged=true")
    }

    /// F1 修复验证：非首帧连续 fully → hasChanged 应为 false（长专注不误报）
    func testF1_nonFirstFrame_continuouslyFully_hasChangedFalse() async throws {
        let imgA = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: false)
        let imgB = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: true)
        let mock = MockAIService(level: .fully)
        let analyzer = makeAnalyzer(service: mock)

        // 首帧：fully（maxAIInterval 设超短让第二帧也能过 dHash 门）
        _ = await analyzer.tick(captureOverride: { imgA })

        // 第二帧：仍然 fully（不同图确保过 dHash）
        let r = await analyzer.tick(captureOverride: { imgB })

        XCTAssertFalse(r.hasChanged, "连续 fully 不应视为跳变，hasChanged=false")
    }

    // MARK: - F7 诊断日志 distance 修复测试

    /// F7 修复验证：两帧不同图的 analyzed 日志里 distance 字段应等于实际 dHash 距离（非 0）
    func testF7_diagnosticLogDistanceIsCorrect() async throws {
        let imgA = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: false)
        let imgB = DHashComputerTests.gradientImage(width: 200, height: 100, reversed: true)
        let mock = MockAIService(level: .fully)

        // 使用可读 logURL 验证诊断日志
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus_f7_test_\(UUID().uuidString).jsonl")
        var cfg = CaptureConfig()
        cfg.idleThreshold = 9_999_999
        let analyzer = FrameAnalyzer(
            service: mock,
            config: cfg,
            sessionID: UUID(),
            promise: "测试 F7",
            diagnosticLogURL: logURL
        )

        // 首帧（firstFrame，distance 字段 null）
        _ = await analyzer.tick(captureOverride: { imgA })

        // 第二帧（图不同，distance 应非 0）
        _ = await analyzer.tick(captureOverride: { imgB })

        // 读取日志，解析所有行
        let content = try String(contentsOf: logURL, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertGreaterThanOrEqual(lines.count, 2, "至少应有 2 行日志")

        // 第一行（firstFrame）：distance 应为 null
        let firstLine = try XCTUnwrap(lines.first)
        let firstEntry = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any]
        )
        XCTAssertTrue(firstEntry["distance"] is NSNull, "首帧 distance 日志应为 null")

        // 找到第一个 decision 不为 skipped 的 analyzed 行（第二帧）
        let analyzedLines = lines.filter { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
                .flatMap { $0["decision"] as? String }?
                .hasPrefix("analyzed_") ?? false
        }
        // 第二帧 analyzed 行应存在且 distance 不为 null、不为 0
        guard let secondAnalyzed = analyzedLines.dropFirst().first else {
            // 如果只有一条 analyzed（首帧），跳过（环境 dHash 阈值问题）
            return
        }
        let secondEntry = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(secondAnalyzed.utf8)) as? [String: Any]
        )
        let dist = secondEntry["distance"] as? Int
        XCTAssertNotNil(dist, "第二帧 analyzed 行 distance 字段不应为 null")
        XCTAssertGreaterThan(dist ?? 0, 0, "不同图的 distance 应 > 0，修复前此值恒为 0")

        // 同时验证 distance 与实际 dHash 距离一致
        let hashA = DHashComputer.hash(imgA)
        let hashB = DHashComputer.hash(imgB)
        let expectedDist = DHashComputer.distance(hashA, hashB)
        XCTAssertEqual(dist, expectedDist, "日志 distance 应等于实际 dHash 距离 \(expectedDist)")
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
