import XCTest
@testable import Vigil

final class ScreenshotStoreTests: XCTestCase {

    // MARK: - 测试 1：正常路径，rootDirectory 在 Application Support 下且能创建文件

    /// 正常情况下，rootDirectory 应指向 Application Support/Focus/Screenshots，
    /// 且该目录存在、可写（能创建临时文件）。
    func testRootDirectoryIsInApplicationSupport() throws {
        let root = ScreenshotStore.rootDirectory

        // 路径应包含 "Application Support"
        XCTAssertTrue(
            root.path.contains("Application Support"),
            "rootDirectory 应在 Application Support 下，实际路径：\(root.path)"
        )

        // 目录应已存在（rootDirectory 内部会 createDirectory）
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir)
        XCTAssertTrue(exists, "rootDirectory 目录应已存在：\(root.path)")
        XCTAssertTrue(isDir.boolValue, "rootDirectory 应是目录：\(root.path)")

        // 应能在该目录下创建文件
        let testFile = root.appendingPathComponent("ScreenshotStoreTests_canWrite.tmp")
        defer { try? FileManager.default.removeItem(at: testFile) }

        XCTAssertNoThrow(
            try "test".write(to: testFile, atomically: true, encoding: .utf8),
            "rootDirectory 应可写"
        )
    }

    // MARK: - 测试 2：newScreenshotURL 前缀与 sessionID 一致

    /// newScreenshotURL 返回的 URL 和 relative 路径的前缀应与 sessionID.uuidString 一致。
    func testNewScreenshotURLPrefixMatchesSessionID() {
        let sessionID = UUID()
        let (fullURL, relative) = ScreenshotStore.newScreenshotURL(sessionID: sessionID)

        // relative 应以 sessionID.uuidString 开头
        XCTAssertTrue(
            relative.hasPrefix(sessionID.uuidString),
            "relative 应以 sessionID 开头，实际：\(relative)"
        )

        // fullURL 路径应包含 sessionID.uuidString
        XCTAssertTrue(
            fullURL.path.contains(sessionID.uuidString),
            "fullURL 应包含 sessionID，实际：\(fullURL.path)"
        )

        // relative 应以 .jpg 结尾
        XCTAssertTrue(relative.hasSuffix(".jpg"), "relative 应以 .jpg 结尾，实际：\(relative)")

        // 清理测试产生的 session 目录
        let sessionDir = ScreenshotStore.rootDirectory.appendingPathComponent(sessionID.uuidString)
        try? FileManager.default.removeItem(at: sessionDir)
    }

    // MARK: - 测试 3：rootDirectory 多次调用返回同一路径（幂等性）

    /// 连续多次调用 rootDirectory 应返回相同的路径（幂等，不会每次生成新路径）。
    func testRootDirectoryIsIdempotent() {
        let url1 = ScreenshotStore.rootDirectory
        let url2 = ScreenshotStore.rootDirectory
        let url3 = ScreenshotStore.rootDirectory

        XCTAssertEqual(url1.path, url2.path, "第 1 次和第 2 次调用应相同")
        XCTAssertEqual(url2.path, url3.path, "第 2 次和第 3 次调用应相同")
    }

    // MARK: - 说明：降级路径测试

    /// 降级路径（Application Support 获取失败 → 回落到 tmp/Focus/Screenshots）难以在单元测试
    /// 中直接触发，原因：FileManager 是系统单例，无法在测试层注入 mock 实现；
    /// 且 macOS 沙盒下 Application Support 几乎不会真正失败。
    ///
    /// 建议通过以下方式交叉验证：
    /// 1. 在模拟器或虚拟机中以只读磁盘挂载的方式触发失败；
    /// 2. 将 ScreenshotStore 重构为依赖注入（接受 FileManager 参数），
    ///    届时可传入 mock FileManager 在测试中强制 url(for:) 抛出错误。
    func testFallbackPathDocumentation() {
        // 本测试仅作文档说明，不做断言。
        // 降级逻辑已在 ScreenshotStore.rootDirectory 中实现，详见 ScreenCaptureManager.swift。
    }
}
