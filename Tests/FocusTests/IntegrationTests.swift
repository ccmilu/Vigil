import XCTest
@testable import Focus

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
}
