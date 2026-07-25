import XCTest
import CoreGraphics
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

    /// 多屏改造风险 1 的实测验证：本地 VLM 是否接受多图消息。
    /// 构造两张内容明显不同的合成图（纯蓝 + 纯红）发双图 analyzeFrame，
    /// 断言返回合法 level 且 reasoning 非空；完整 reasoning 打印出来，
    /// 供人工判断模型是否真看了两张图（理想情况会提到蓝/红两色或两块屏幕）。
    func testAnalyzeFrame_twoImages_realLMStudio() async throws {
        let service = OpenAICompatibleService()
        let blue = Self.solidColorImage(width: 320, height: 200, r: 0, g: 0, b: 255)
        let red = Self.solidColorImage(width: 320, height: 200, r: 255, g: 0, b: 0)
        let blueJPEG = try ScreenCaptureManager.jpegData(blue)
        let redJPEG = try ScreenCaptureManager.jpegData(red)

        let input = FrameAnalysisInput(
            promise: "写一份本周的工作周报",
            appName: "Pages",
            windowTitles: "周报.pages",
            screenshotJPEGs: [blueJPEG, redJPEG]
        )
        let result = try await service.analyzeFrame(input)
        // 不假设具体 level（模型对纯色图的判断策略不一），但 reasoning 必须非空——
        // 说明端点接受了多图消息并返回了合法 JSON
        XCTAssertFalse(result.reasoning.isEmpty, "reasoning 不应为空（多图消息应被接受）")
        print("[Integration] two-images level=\(result.level.rawValue)")
        print("[Integration] two-images reasoning=\(result.reasoning)")
        print("[Integration] two-images reminder=\(result.reminder)")
    }

    /// 纯色 RGB 合成图（供多图集成测试构造内容明显不同的两张图）。
    private static func solidColorImage(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }
}
