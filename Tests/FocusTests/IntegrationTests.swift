import XCTest
import CoreGraphics
import AppKit
@testable import Vigil

/// 真集成测试：会向 DemoConfig 配的真实 LM Studio 发请求。
///
/// 默认 skip，只在环境变量 RUN_INTEGRATION=1 时跑。
/// scripts/test.sh 提供 --integration 一键开关。
final class IntegrationTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        if ProcessInfo.processInfo.environment["RUN_INTEGRATION"] != "1" {
            throw XCTSkip("set RUN_INTEGRATION=1 to enable")
        }
    }

    func testAnalyzeTask_realLMStudio() async throws {
        let service = OpenAICompatibleService()
        let result = try await service.analyzeTask("写一份本周的工作周报")
        // 不假设具体 taskType，但要求字段合法
        XCTAssertTrue(
            [.writing, .other, .development, .research, .design].contains(result.taskType),
            "got: \(result.taskType)"
        )
        print("[Integration] taskType=\(result.taskType) suggestion=\(result.suggestion ?? "<nil>")")
    }

    func testAnalyzeTask_vaguePromise() async throws {
        let service = OpenAICompatibleService()
        let result = try await service.analyzeTask("学习")
        // 模糊的承诺，期望模型给一个 suggestion
        // 但不强制（不同模型策略不同），只打印观测
        print("[Integration] vague taskType=\(result.taskType) suggestion=\(result.suggestion ?? "<nil>")")
    }

    /// 多屏改造风险 1 的实测验证（升级版）：本地 VLM 是否"真在读图"。
    /// 构造两张 320×200 合成图，各写大而清晰的独特文字：
    /// 图 1 深色底浅色字 "LEFT-CODE-12345"（模拟代码屏），
    /// 图 2 高对比亮色底深色字 "RIGHT-VIDEO-67890"（模拟视频屏）。
    /// 断言保持宽松（level 合法 + reasoning 非空，不为难本地 4B 小模型），
    /// 完整 reasoning 打印出来——若提及任一独特字符串/文字内容，
    /// 即为"模型真在读图"的铁证；若只复述文本元数据，如实记录（能力边界，非链路问题）。
    func testAnalyzeFrame_twoImages_realLMStudio() async throws {
        let service = OpenAICompatibleService()
        // 图 1：深色底 + 白字，模拟代码编辑器屏
        let code = Self.textImage(
            width: 320, height: 200,
            lines: ["LEFT-CODE", "12345"],
            bgR: 15, bgG: 20, bgB: 35,
            textColor: .white
        )
        // 图 2：亮黄底 + 深红字，与图 1 强对比，模拟视频屏
        let video = Self.textImage(
            width: 320, height: 200,
            lines: ["RIGHT-VIDEO", "67890"],
            bgR: 250, bgG: 220, bgB: 40,
            textColor: .red
        )
        let codeJPEG = try ScreenCaptureManager.jpegData(code)
        let videoJPEG = try ScreenCaptureManager.jpegData(video)

        let input = FrameAnalysisInput(
            promise: "写一份本周的工作周报",
            appName: "Pages",
            windowTitles: "周报.pages",
            screenshotJPEGs: [codeJPEG, videoJPEG]
        )
        let result = try await service.analyzeFrame(input)
        // level 合法（类型即 FocusLevel，枚举集合显式断言一遍）+ reasoning 非空——
        // 说明端点接受了多图消息并返回了合法 JSON；不要求模型判对（纯色合成图本就非常规屏幕）
        XCTAssertTrue(
            [.fully, .wandering, .distracted, .idle].contains(result.level),
            "got: \(result.level)"
        )
        XCTAssertFalse(result.reasoning.isEmpty, "reasoning 不应为空（多图消息应被接受）")
        print("[Integration] two-images level=\(result.level.rawValue)")
        print("[Integration] two-images reasoning=\(result.reasoning)")
        print("[Integration] two-images reminder=\(result.reminder)")
        // 读图有效性观测（不断言，仅打印供人工判定）：
        let lower = result.reasoning.lowercased()
        let hits = ["left-code", "12345", "right-video", "67890"].filter { lower.contains($0) }
        print("[Integration] two-images unique-string hits=\(hits)")
    }

    /// 文字合成图（供多图集成测试构造"模型必须真读图才能说出内容"的两张图）。
    /// CGContext 填纯色底后用 AppKit 画大号粗体文字（字号 44，分两行排版保证 320 宽内完整可读）。
    private static func textImage(
        width: Int, height: Int,
        lines: [String],
        bgR: CGFloat, bgG: CGFloat, bgB: CGFloat,
        textColor: NSColor
    ) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: bgR / 255, green: bgG / 255, blue: bgB / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // flipped=true 让坐标变左上原点，文字排版更直观
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 44, weight: .bold),
            .foregroundColor: textColor
        ]
        for (i, line) in lines.enumerated() {
            // 每行高约 60pt，x=10 保证最长行（11 字符等宽 44pt ≈ 290pt）在 320 宽内
            NSAttributedString(string: line, attributes: attrs)
                .draw(at: NSPoint(x: 10, y: 30 + i * 60))
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }
}
