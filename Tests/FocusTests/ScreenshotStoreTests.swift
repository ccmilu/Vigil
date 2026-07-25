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

    // MARK: - 多屏改造：sibling 命名推导（_pN）

    /// siblingScreenshotURL：index 2/3 应推导出 `<stem>_p2.jpg` / `<stem>_p3.jpg`，与第一张同目录。
    func testSiblingScreenshotURLNaming() {
        let first = URL(fileURLWithPath: "/tmp/some-session/20260725_120000000.jpg")

        let p2 = ScreenshotStore.siblingScreenshotURL(firstURL: first, index: 2)
        XCTAssertEqual(p2.lastPathComponent, "20260725_120000000_p2.jpg")
        XCTAssertEqual(p2.deletingLastPathComponent().path, first.deletingLastPathComponent().path,
                       "sibling 应与第一张同目录")

        let p3 = ScreenshotStore.siblingScreenshotURL(firstURL: first, index: 3)
        XCTAssertEqual(p3.lastPathComponent, "20260725_120000000_p3.jpg")
    }

    // MARK: - 多屏改造：existingScreenshotURLs 连续探测

    private func cleanupSession(_ sessionID: UUID) {
        let dir = ScreenshotStore.rootDirectory.appendingPathComponent(sessionID.uuidString)
        try? FileManager.default.removeItem(at: dir)
    }

    /// 第一张不存在 → 返回空数组。
    func testExistingScreenshotURLs_firstMissing_returnsEmpty() {
        let urls = ScreenshotStore.existingScreenshotURLs(relativePath: "\(UUID().uuidString)/不存在的文件.jpg")
        XCTAssertTrue(urls.isEmpty, "第一张不存在应返回空数组")
    }

    /// 旧单屏数据（只有第一张，无 _pN）→ 返回单元素数组（向后兼容）。
    func testExistingScreenshotURLs_singleScreenLegacy_returnsSingleElement() {
        let sessionID = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_753_400_000)  // 固定时间戳避免撞名
        let (firstURL, relative) = ScreenshotStore.newScreenshotURL(sessionID: sessionID, at: fixedDate)
        defer { cleanupSession(sessionID) }
        // 只写第一张
        try! Data("jpg".utf8).write(to: firstURL)

        let urls = ScreenshotStore.existingScreenshotURLs(relativePath: relative)
        XCTAssertEqual(urls.count, 1, "旧单屏数据应返回单元素数组")
        XCTAssertEqual(urls[0].lastPathComponent, firstURL.lastPathComponent)
    }

    /// 双屏数据（第一张 + _p2）→ 返回两个元素，顺序 第一张 → _p2。
    func testExistingScreenshotURLs_twoScreens_returnsInOrder() {
        let sessionID = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_753_400_001)
        let (firstURL, relative) = ScreenshotStore.newScreenshotURL(sessionID: sessionID, at: fixedDate)
        defer { cleanupSession(sessionID) }
        try! Data("jpg".utf8).write(to: firstURL)
        let p2 = ScreenshotStore.siblingScreenshotURL(firstURL: firstURL, index: 2)
        try! Data("jpg".utf8).write(to: p2)

        let urls = ScreenshotStore.existingScreenshotURLs(relativePath: relative)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].lastPathComponent, firstURL.lastPathComponent)
        XCTAssertEqual(urls[1].lastPathComponent, p2.lastPathComponent)
    }

    /// 断号即停：存在 第一张 + _p2 + _p4（缺 _p3）→ 只返回 [第一张, _p2]，
    /// 容忍 Finder 手动删图造成的空洞，不向后续探测。
    func testExistingScreenshotURLs_gapStopsProbing() {
        let sessionID = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_753_400_002)
        let (firstURL, relative) = ScreenshotStore.newScreenshotURL(sessionID: sessionID, at: fixedDate)
        defer { cleanupSession(sessionID) }
        try! Data("jpg".utf8).write(to: firstURL)
        let p2 = ScreenshotStore.siblingScreenshotURL(firstURL: firstURL, index: 2)
        try! Data("jpg".utf8).write(to: p2)
        // 故意跳过 _p3，直接写 _p4 制造断号
        let p4 = ScreenshotStore.siblingScreenshotURL(firstURL: firstURL, index: 4)
        try! Data("jpg".utf8).write(to: p4)

        let urls = ScreenshotStore.existingScreenshotURLs(relativePath: relative)
        XCTAssertEqual(urls.count, 2, "断号即停：_p3 缺失后不应继续探测 _p4")
        XCTAssertEqual(urls[0].lastPathComponent, firstURL.lastPathComponent)
        XCTAssertEqual(urls[1].lastPathComponent, p2.lastPathComponent)
    }
}
