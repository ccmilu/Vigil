import XCTest
import CoreGraphics
import SwiftData
@testable import Vigil

/// ralph 交叉测试（独立上下文）：多显示器改造的对抗性补盲。
/// 目标不是重复已有用例，而是尽一切努力让被测链路失败；
/// 打不破的行为固化为语义锚点（注释标明"锚点"），发现的问题报给 lead。
final class MultiDisplayAdversarialTests: XCTestCase {

    // MARK: - 共用 helper

    /// 默认禁用 idle 闸门；其余阈值由调用方按需覆盖。
    private func makeAnalyzer(
        service: AIService,
        config: CaptureConfig? = nil,
        logURL: URL? = nil
    ) -> FrameAnalyzer {
        var cfg = config ?? CaptureConfig()
        cfg.idleThreshold = 9_999_999
        return FrameAnalyzer(
            service: service,
            config: cfg,
            sessionID: UUID(),
            promise: "对抗测试",
            diagnosticLogURL: logURL ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("vigil_adv_\(UUID().uuidString).jsonl")
        )
    }

    /// 宽度超 JPEG 单维上限（65535）的图：
    /// downscale 算出 0 高新尺寸 → CGContext 创建失败返回原图 → CGImageDestinationFinalize 必失败。
    /// 已用独立脚本探测验证：100000x10 必抛 encodeFailed。
    private func unencodableImage() -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 100_000, height: 10,
            bitsPerComponent: 8, bytesPerRow: 100_000 * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 100_000, height: 10))
        return ctx.makeImage()!
    }

    private func grad(_ reversed: Bool, _ offset: Int = 0) -> CGImage {
        DHashComputerTests.gradientImage(width: 200, height: 100, reversed: reversed, brightnessOffset: offset)
    }

    // MARK: - 任务 1：首帧 dhashHex 落 max 屏（语义锚点，非 bug）

    /// 多屏 firstFrame：全屏距离并列 Int.max → 并列规则"小编号屏胜出"，
    /// 落库 dhashHex 是小编号屏的哈希，**不是 minX 数组第一屏、也不一定是主屏**。
    /// 此处数组第一屏故意给大编号 displayID=100，小编号屏 displayID=3 放数组第二位。
    func testFirstFrame_multiDisplay_hashAnchorsToSmallerDisplayID_notArrayFirst() async throws {
        let imgNormal = grad(false)
        let imgReversed = grad(true)
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigil_adv_first_\(UUID().uuidString).jsonl")
        let analyzer = makeAnalyzer(service: RecordingAIService(level: .fully), logURL: logURL)

        let frames = [
            DisplayFrame(displayID: 100, image: imgNormal),   // minX 最左屏，但 displayID 大
            DisplayFrame(displayID: 3, image: imgReversed)    // 数组第二位，但 displayID 小
        ]
        let r = await analyzer.tick(captureOverride: { frames })

        guard case .analyzed(let reason, let dist, _, let fromAI) = r.decision else {
            return XCTFail("首帧应 analyzed；实际 \(r.decision)")
        }
        XCTAssertEqual(reason, .firstFrame)
        XCTAssertNil(dist)
        XCTAssertTrue(fromAI)
        // 锚点：hash 是小编号屏（3）的哈希，不是数组第一屏（100）的
        XCTAssertEqual(r.hash, DHashComputer.hash(imgReversed),
            "firstFrame 并列 Int.max 时落库 hash 应是小编号屏的哈希")
        XCTAssertNotEqual(r.hash, DHashComputer.hash(imgNormal))

        // 诊断 jsonl 同步落同一个 hash（读写两侧一致）
        let content = try String(contentsOf: logURL, encoding: .utf8)
        let firstLine = try XCTUnwrap(content.split(separator: "\n").first.map(String.init))
        let entry = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any]
        )
        XCTAssertEqual(entry["hash"] as? String, DHashComputer.hash(imgReversed).hexString,
            "jsonl 的 hash 字段应与落库一致（小编号屏）")
    }

    // MARK: - 任务 2：部分屏编码失败降级

    /// 一屏 JPEG 编码失败：AI 收到图数 < 屏数，tick 不崩、level/reason 正常；
    /// screenshotCount 与实际附图自洽（FrameAnalyzer 只传成功编码的图 → OpenAICompatibleService
    /// 用 jpegs.count 生成 prompt——1 张图时无多屏说明段，由 testAnalyzeFrame_endToEnd 锁定）。
    func testPartialEncodeFailure_oneScreenDropped_aiReceivesFewerImages() async throws {
        let good = grad(false)
        let bad = unencodableImage()
        // 前提钉死：若未来 ImageIO 能编码此图，本测试应重写而不是静默失效
        XCTAssertThrowsError(try ScreenCaptureManager.jpegData(bad), "前提：坏图必须编码失败")

        let recorder = RecordingAIService(level: .wandering)
        let analyzer = makeAnalyzer(service: recorder)
        let frames = [
            DisplayFrame(displayID: 1, image: good),
            DisplayFrame(displayID: 2, image: bad)   // 此屏编码失败
        ]
        let r = await analyzer.tick(captureOverride: { frames })

        guard case .analyzed(let reason, _, let level, let fromAI) = r.decision else {
            return XCTFail("部分编码失败不应让 tick 崩；实际 \(r.decision)")
        }
        XCTAssertEqual(reason, .firstFrame)
        XCTAssertEqual(level, .wandering)
        XCTAssertTrue(fromAI, "仍有 1 张图可发，AI 应被调用")

        let recorded1 = await recorder.firstFrameInput
        let input = try XCTUnwrap(recorded1)
        XCTAssertEqual(input.screenshotJPEGs.count, 1,
            "一屏编码失败 → AI 应收 1 张图（屏数 2 > 图数 1）")
        // 幸存的是好屏那张（jpegData 对同一输入确定性编码）
        XCTAssertEqual(input.screenshotJPEGs[0], try ScreenCaptureManager.jpegData(good),
            "幸存的图应是编码成功那屏的 JPEG")
    }

    /// 全部屏编码失败：不调 AI（jpegs 空直接回落），level 落 lastLevel ?? .wandering；
    /// hash 不写回 → 下一帧仍是 firstFrame（重试编码语义）。锚点。
    func testAllEncodeFailure_aiNotInvoked_firstFrameRepeatsNextTick() async throws {
        let recorder = RecordingAIService(level: .fully)
        let analyzer = makeAnalyzer(service: recorder)
        let frames = [
            DisplayFrame(displayID: 1, image: unencodableImage()),
            DisplayFrame(displayID: 2, image: unencodableImage())
        ]

        let r1 = await analyzer.tick(captureOverride: { frames })
        guard case .analyzed(let reason1, _, let level1, let fromAI1) = r1.decision else {
            return XCTFail("全失败应走 analyzed 回落分支；实际 \(r1.decision)")
        }
        XCTAssertEqual(reason1, .firstFrame)
        XCTAssertEqual(level1, .wandering, "lastLevel 为 nil 应落 .wandering")
        XCTAssertFalse(fromAI1, "全部编码失败不得调 AI")
        XCTAssertEqual(r1.images.count, 2, "images 仍带回供 persistTick 尝试落盘")
        let callsAfterR1 = await recorder.callCount
        XCTAssertEqual(callsAfterR1, 0, "jpegs 为空时 AI 一次都不应被调")

        // 第二帧：hash 未写回 → 仍是 firstFrame（下帧重试语义锚点）
        let r2 = await analyzer.tick(captureOverride: { frames })
        guard case .analyzed(let reason2, _, _, let fromAI2) = r2.decision else {
            return XCTFail("实际 \(r2.decision)")
        }
        XCTAssertEqual(reason2, .firstFrame, "编码失败不写回 hash → 下帧应仍是 firstFrame")
        XCTAssertFalse(fromAI2)
        let callsAfterR2 = await recorder.callCount
        XCTAssertEqual(callsAfterR2, 0)
    }

    // MARK: - 任务 4：MultiDisplayDHash 补盲

    /// 单屏退化：MultiDisplayDHash 的 max 必须与旧 DHashComputer.distance 完全一致（回归锚点）。
    func testSingleDisplay_degeneratesToLegacyDistance() {
        let h1 = DHashComputer.hash(grad(false))
        let h2 = DHashComputer.hash(grad(true))
        let legacy = DHashComputer.distance(h1, h2)
        XCTAssertGreaterThan(legacy, 0, "前提：两图哈希应不同")

        let r = MultiDisplayDHash.distances(old: [7: h1], new: [7: h2])
        XCTAssertEqual(r.perDisplay[7], legacy)
        XCTAssertEqual(r.max, legacy, "单屏 max 必须等于旧版单屏距离")
        XCTAssertEqual(r.maxDisplayID, 7)
    }

    /// old 只记录中间屏，两块新屏并列 Int.max → 小编号新屏胜出（确定性锚点）。
    func testTwoNewDisplays_tieAmongNewOnes_smallerIDWins() {
        let zeros = Data(repeating: 0x00, count: 32)
        let ones = Data(repeating: 0xFF, count: 32)
        let r = MultiDisplayDHash.distances(
            old: [2: zeros],
            new: [1: ones, 2: zeros, 3: ones]   // 屏 1/3 都是新插入
        )
        XCTAssertEqual(r.perDisplay[1], Int.max)
        XCTAssertEqual(r.perDisplay[2], 0)
        XCTAssertEqual(r.perDisplay[3], Int.max)
        XCTAssertEqual(r.max, Int.max)
        XCTAssertEqual(r.maxDisplayID, 1, "两块新屏并列 Int.max → 小编号屏胜出")
    }

    /// old 里混进损坏哈希（长度 16 ≠ 32）→ distance 得 Int.max → 强制分析。
    /// 安全侧行为：数据损坏宁多调 AI 也不静默 skip。锚点。
    func testCorruptOldHash_lengthMismatch_forcesMaxDistance() {
        let shortHash = Data(repeating: 0xAB, count: 16)   // 损坏：只有 128 bit
        let newHash = Data(repeating: 0xAB, count: 32)
        let r = MultiDisplayDHash.distances(old: [1: shortHash], new: [1: newHash])
        XCTAssertEqual(r.perDisplay[1], Int.max,
            "长度不等的哈希应得 Int.max（DHashComputer.distance 的既有约定）")
        XCTAssertEqual(r.max, Int.max)
        XCTAssertEqual(r.maxDisplayID, 1)
    }

    // MARK: - 任务 6：siblingScreenshotURL 命名

    /// index=10 的命名推导（现有用例只覆盖 2/3）。
    /// precondition(index >= 2) 无法在不崩的前提下测，此处以 index≥2 全部成立做文档化锚点。
    func testSiblingScreenshotURL_index10() {
        let first = URL(fileURLWithPath: "/tmp/any-session/20260725_235959123.jpg")
        let p10 = ScreenshotStore.siblingScreenshotURL(firstURL: first, index: 10)
        XCTAssertEqual(p10.lastPathComponent, "20260725_235959123_p10.jpg")
        XCTAssertEqual(p10.deletingLastPathComponent().path,
                       first.deletingLastPathComponent().path, "sibling 与第一张同目录")
    }

    // MARK: - 任务 5：existingScreenshotURLs 边界

    private func cleanupSessionDir(_ sessionID: UUID) {
        let dir = ScreenshotStore.rootDirectory.appendingPathComponent(sessionID.uuidString)
        try? FileManager.default.removeItem(at: dir)
    }

    /// _p2 存在但第一张不存在 → 空数组（persistTick 第一张写失败但副屏写成功的场景）。
    func testExistingScreenshotURLs_onlyP2ExistsFirstMissing_returnsEmpty() throws {
        let sessionID = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_754_100_000)
        let (firstURL, relative) = ScreenshotStore.newScreenshotURL(sessionID: sessionID, at: fixedDate)
        defer { cleanupSessionDir(sessionID) }
        // 只写 _p2，故意不写第一张
        let p2 = ScreenshotStore.siblingScreenshotURL(firstURL: firstURL, index: 2)
        try Data("jpg".utf8).write(to: p2)

        let urls = ScreenshotStore.existingScreenshotURLs(relativePath: relative)
        XCTAssertTrue(urls.isEmpty,
            "第一张缺失即返回空（guard first exists），即使 _p2 在盘上也不返回——UI 走无截图分支")
    }

    /// relativePath 为空串：store 层会把 rootDirectory 自身当"第一张"返回（目录存在）。
    /// 锚点记录实际行为；UI 层 screenshotURLs 有 `!p.isEmpty` guard 挡住，不到达这里。
    func testExistingScreenshotURLs_emptyRelativePath_returnsRootDir_documented() {
        let urls = ScreenshotStore.existingScreenshotURLs(relativePath: "")
        XCTAssertEqual(urls.count, 1,
            "空串 → rootDirectory 自身存在 → 返回 [root]（目录 URL）。锚点：UI 层已 guard 空串")
        XCTAssertTrue(urls[0].hasDirectoryPath, "返回的是目录而非图片文件")
    }

    /// 非法相对路径 "..":路径穿越到父目录（存在）→ 返回 1 个目录 URL。
    /// 锚点记录实际行为：screenshotLocalPath 生产上只由 newScreenshotURL 生成（UUID/时间戳.jpg），
    /// 不可达此分支；若未来加防御应返回空。报 lead 知悉（低危）。
    func testExistingScreenshotURLs_dotDotTraversal_returnsParentDir_documented() {
        let urls = ScreenshotStore.existingScreenshotURLs(relativePath: "..")
        XCTAssertEqual(urls.count, 1, ".. 穿越到存在的父目录 → 返回 [父目录 URL]（锚点，低危）")
        XCTAssertTrue(urls[0].path.hasSuffix(".."),
            "返回的是未解析的穿越路径（URL.hasDirectoryPath 对 .. 为 false，不能靠它识别目录）")
    }

    // MARK: - 任务 9：双屏 tick 全链路

    /// 双屏均稳（一屏距离 0、一屏小变化 < 阈值）→ skippedDhashStable，
    /// 且 distance = 两屏距离的 **max**（不是 min / 不是数组第一屏）；skip 帧 hash 落 max 屏。
    func testDualDisplay_bothStable_skipsWithMaxDistanceAndMaxScreenHash() async throws {
        let imgA = grad(false)
        let imgB = grad(true)
        let imgB2 = grad(true, 25)   // 屏 22 小变化（亮度+25 → 少量 bit 翻转）

        var cfg = CaptureConfig()
        cfg.dhashThreshold = 200      // 确保小变化不越阈值，专注验证 max 语义
        cfg.maxAIInterval = 3600
        let analyzer = makeAnalyzer(service: RecordingAIService(level: .fully), config: cfg)

        let t0 = Date(timeIntervalSince1970: 1_754_200_000)
        _ = await analyzer.tick(now: t0, captureOverride: {
            [DisplayFrame(displayID: 11, image: imgA),
             DisplayFrame(displayID: 22, image: imgB)]
        })

        let expectedE2 = DHashComputer.distance(DHashComputer.hash(imgB), DHashComputer.hash(imgB2))
        XCTAssertGreaterThan(expectedE2, 0, "前提：亮度+25 应产生非零距离")
        XCTAssertLessThan(expectedE2, 200, "前提：小变化不越阈值")

        let r2 = await analyzer.tick(now: t0.addingTimeInterval(5), captureOverride: {
            [DisplayFrame(displayID: 11, image: imgA),    // 屏 11 完全不动（距离 0）
             DisplayFrame(displayID: 22, image: imgB2)]
        })
        // 屏 11 距离 0、屏 22 距离 expectedE2 → max = expectedE2
        XCTAssertEqual(r2.decision, .skippedDhashStable(distance: expectedE2),
            "skip 的 distance 应是两屏 max（屏 22 的距离），不是 0 也不是屏 11")
        XCTAssertEqual(r2.hash, DHashComputer.hash(imgB2),
            "skip 帧落库 hash 应是 max 屏（22）的本帧哈希")
    }

    /// 一屏剧变 → analyzed；落库 distance/hex 对应**剧变屏**。
    /// 对抗点：剧变屏 displayID=3 放数组第二位，稳定屏 displayID=100 放第一位——
    /// 验证 max 选中的是"变化最大的屏"，与数组顺序无关。
    func testDualDisplay_oneDrasticChange_analyzed_distanceAndHashFromChangedScreen() async throws {
        let stable = grad(false)
        let imgA = grad(true)
        let imgAReversed = grad(false)   // 与 imgA 完全相反 → 距离 > 50（超阈值 30）
        let analyzer = makeAnalyzer(service: RecordingAIService(level: .fully))

        let t0 = Date(timeIntervalSince1970: 1_754_201_000)
        _ = await analyzer.tick(now: t0, captureOverride: {
            [DisplayFrame(displayID: 100, image: stable),
             DisplayFrame(displayID: 3, image: imgA)]
        })
        let r2 = await analyzer.tick(now: t0.addingTimeInterval(5), captureOverride: {
            [DisplayFrame(displayID: 100, image: stable),       // 稳定
             DisplayFrame(displayID: 3, image: imgAReversed)]   // 剧变
        })

        let expectedDist = DHashComputer.distance(DHashComputer.hash(imgA), DHashComputer.hash(imgAReversed))
        XCTAssertGreaterThan(expectedDist, 30, "前提：反色图距离超阈值")

        guard case .analyzed(let reason, let dist, _, let fromAI) = r2.decision else {
            return XCTFail("一屏剧变应 analyzed；实际 \(r2.decision)")
        }
        XCTAssertEqual(reason, .dhashChanged)
        XCTAssertEqual(dist, expectedDist, "落库 distance 应等于剧变屏的距离")
        XCTAssertTrue(fromAI)
        XCTAssertEqual(r2.hash, DHashComputer.hash(imgAReversed),
            "落库 hash 应来自剧变屏（3）而非数组第一屏（100）")
    }

    /// 新屏加入（第二 tick 多一个 displayID）→ Int.max 必触发 analyzed；
    /// 诊断 jsonl 的 distance 字段如实记 Int.max（不是 null、不是 0）。
    func testNewDisplayAttached_secondTick_forcesAnalysis_intMaxDistanceLogged() async throws {
        let imgA = grad(false)
        let imgB = grad(true)
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigil_adv_attach_\(UUID().uuidString).jsonl")
        let analyzer = makeAnalyzer(service: RecordingAIService(level: .fully), logURL: logURL)

        let t0 = Date(timeIntervalSince1970: 1_754_202_000)
        _ = await analyzer.tick(now: t0, captureOverride: {
            [DisplayFrame(displayID: 5, image: imgA)]
        })
        let r2 = await analyzer.tick(now: t0.addingTimeInterval(5), captureOverride: {
            [DisplayFrame(displayID: 5, image: imgA),    // 旧屏完全不动
             DisplayFrame(displayID: 8, image: imgB)]    // 热插入新屏
        })

        guard case .analyzed(let reason, let dist, _, let fromAI) = r2.decision else {
            return XCTFail("新屏加入必须 analyzed；实际 \(r2.decision)")
        }
        XCTAssertEqual(reason, .dhashChanged, "未到 maxAIInterval，触发原因应是 dhashChanged")
        XCTAssertEqual(dist, Int.max, "新屏距离应是 Int.max")
        XCTAssertTrue(fromAI)

        // jsonl 第二行 distance == Int.max（F7 修复的 distance 真实性在多屏新屏场景保持）
        let lines = try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines.count, 2)
        let entry = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any]
        )
        XCTAssertEqual(entry["distance"] as? Int, Int.max,
            "新屏帧的日志 distance 应如实记录 Int.max")
        XCTAssertEqual(entry["decision"] as? String, "analyzed_dhashChanged_ai")
    }

    /// 屏移除 → 正常 skip 不崩；剪枝只发生在 AI 写回点：
    /// 移除后再插回（期间剩余屏有过一次 analyzed）→ 旧屏记录已被剪 → Int.max 再触发。
    func testDisplayRemoved_noCrash_pruneHappensAtAIWriteBack() async throws {
        let imgA = grad(false)
        let imgAReversed = grad(true)
        let imgB = grad(true, 60)
        let analyzer = makeAnalyzer(service: RecordingAIService(level: .fully))

        let t0 = Date(timeIntervalSince1970: 1_754_203_000)
        // t1：双屏 firstFrame
        let r1 = await analyzer.tick(now: t0, captureOverride: {
            [DisplayFrame(displayID: 7, image: imgA),
             DisplayFrame(displayID: 9, image: imgB)]
        })
        guard case .analyzed = r1.decision else { return XCTFail("t1 应 analyzed；\(r1.decision)") }

        // t2：屏 9 拔除，屏 7 不动 → skip，不崩
        let r2 = await analyzer.tick(now: t0.addingTimeInterval(5), captureOverride: {
            [DisplayFrame(displayID: 7, image: imgA)]
        })
        guard case .skippedDhashStable = r2.decision else {
            return XCTFail("屏移除 + 余屏不动应 skip；实际 \(r2.decision)")
        }

        // t3：屏 7 剧变 → analyzed（写回点把屏 9 的旧哈希剪掉）
        let r3 = await analyzer.tick(now: t0.addingTimeInterval(10), captureOverride: {
            [DisplayFrame(displayID: 7, image: imgAReversed)]
        })
        guard case .analyzed(let reason3, _, _, _) = r3.decision else {
            return XCTFail("t3 应 analyzed；实际 \(r3.decision)")
        }
        XCTAssertEqual(reason3, .dhashChanged)

        // t4：屏 9 插回（带着与 t1 相同的画面）→ 因 t3 已剪枝 → 视为新屏 Int.max → 必 analyzed
        let r4 = await analyzer.tick(now: t0.addingTimeInterval(15), captureOverride: {
            [DisplayFrame(displayID: 7, image: imgAReversed),
             DisplayFrame(displayID: 9, image: imgB)]
        })
        guard case .analyzed(let reason4, let dist4, _, _) = r4.decision else {
            return XCTFail("插回屏应触发 analyzed；实际 \(r4.decision)")
        }
        XCTAssertEqual(reason4, .dhashChanged)
        XCTAssertEqual(dist4, Int.max, "被剪枝后插回的屏应视为新屏（Int.max）")
        XCTAssertEqual(r4.hash, DHashComputer.hash(imgB), "max 落在插回屏（9）上")
    }

    /// captureOverride 返回空数组（生产 captureAllDisplays 不会返回空，但 override 可能）→ skippedNoWindows。
    func testCaptureOverride_emptyArray_skippedNoWindows() async {
        let analyzer = makeAnalyzer(service: RecordingAIService(level: .fully))
        let r = await analyzer.tick(captureOverride: { [] })
        XCTAssertEqual(r.decision, .skippedNoWindows, "空帧数组保护：应 skippedNoWindows 而非崩溃")
    }

    /// captureOverride 抛非 CaptureError 的任意错误 → generic catch → skippedNoWindows。
    func testCaptureOverride_arbitraryError_skippedNoWindows() async {
        let analyzer = makeAnalyzer(service: RecordingAIService(level: .fully))
        let r = await analyzer.tick(captureOverride: {
            throw NSError(domain: "adversarial.boom", code: 42, userInfo: nil)
        })
        XCTAssertEqual(r.decision, .skippedNoWindows,
            "任意截屏异常应被 generic catch 兜成 skippedNoWindows")
    }

    // MARK: - 任务 10：自选对抗场景

    /// 并发：AI 在飞期间第二个 tick → skippedAIBusy（Gate 2），AI 只被调一次。
    /// 用闸门 mock 保证时序确定性：等 tick1 确实进入 analyzeFrame（isAIBusy=true）后再跑 tick2。
    func testConcurrentTick_whileAIBusy_secondTickSkippedAIBusy() async throws {
        let img = grad(false)
        let gated = GatedRecordingAIService(level: .fully)
        await gated.setHold(true)
        let analyzer = makeAnalyzer(service: gated)

        let t1 = Task { await analyzer.tick(captureOverride: { single(img) }) }

        // 轮询等 tick1 进入 AI 调用（此时 isAIBusy 必为 true），5s 超时兜底防挂死
        let deadline = Date().addingTimeInterval(5)
        while await gated.callCount == 0 {
            if Date() > deadline {
                await gated.setHold(false)
                _ = await t1.value
                return XCTFail("tick1 未在 5s 内进入 AI 调用")
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // tick2：AI 在飞 → Gate 2 拦截
        let r2 = await analyzer.tick(captureOverride: { single(img) })
        XCTAssertEqual(r2.decision, .skippedAIBusy, "AI 在飞期间的 tick 应 skippedAIBusy")

        await gated.setHold(false)
        let r1 = await t1.value
        guard case .analyzed(let reason, _, _, let fromAI) = r1.decision else {
            return XCTFail("tick1 应 analyzed；实际 \(r1.decision)")
        }
        XCTAssertEqual(reason, .firstFrame)
        XCTAssertTrue(fromAI)
        let gatedCalls = await gated.callCount
        XCTAssertEqual(gatedCalls, 1, "AI 只应被调用一次")
    }

    /// 同一 tick 内两帧携带相同 displayID（captureOverride 误用/虚拟屏重叠）：
    /// 哈希字典后写覆盖先写（last wins），但两张图都发给 AI。锚点记录实际行为。
    func testDuplicateDisplayID_sameTick_lastHashWins_documented() async throws {
        let imgA = grad(false)
        let imgB = grad(true)
        let recorder = RecordingAIService(level: .fully)
        let analyzer = makeAnalyzer(service: recorder)
        let frames = [
            DisplayFrame(displayID: 5, image: imgA),
            DisplayFrame(displayID: 5, image: imgB)   // 同 displayID：字典坍塌为 1 键
        ]
        let r = await analyzer.tick(captureOverride: { frames })

        guard case .analyzed = r.decision else {
            return XCTFail("重复 displayID 不应崩；实际 \(r.decision)")
        }
        XCTAssertEqual(r.hash, DHashComputer.hash(imgB),
            "同 displayID 后写覆盖先写 → 落库 hash 是第二帧的（锚点）")
        let recorded2 = await recorder.firstFrameInput
        let input = try XCTUnwrap(recorded2)
        XCTAssertEqual(input.screenshotJPEGs.count, 2,
            "两帧仍各编码一张发给 AI（hash 坍塌不影响发图数）")
    }

    // MARK: - 任务 7：多图 chatVision 请求体

    override func setUp() {
        super.setUp()
        AdvStubProtocol.responder = nil
    }

    private func advStubSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [AdvStubProtocol.self]
        return URLSession(configuration: cfg)
    }

    /// 3 张图（远程 host）：content.count == 4（text + 3 image_url），
    /// 顺序 text → 图1 → 图2 → 图3（= minX 从左到右），每张 image_url 独立且都带 detail:"low"。
    func testChatVision_threeImages_remote_contentCount4_eachIndependentWithDetail() async throws {
        let box = JSONBox()
        AdvStubProtocol.responder = { request in
            let body = request.advHttpBodyData ?? Data()
            box.set(try! JSONSerialization.jsonObject(with: body) as! [String: Any])
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(advFrameOKBody.utf8))
        }
        let service = OpenAICompatibleService(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            model: "gpt-4o-mini", apiKey: "k", session: advStubSession()
        )
        _ = try await service.chatVision(
            system: "s", user: "u",
            imagesJPEG: [Data("img-one".utf8), Data("img-two".utf8), Data("img-three".utf8)],
            temperature: 0.3
        )

        let json = try XCTUnwrap(box.value)
        let messages = json["messages"] as! [[String: Any]]
        let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 4, "3 张图 → text + 3 个 image_url")
        XCTAssertEqual(content[0]["type"] as? String, "text")
        let expectedPayloads = [
            Data("img-one".utf8).base64EncodedString(),
            Data("img-two".utf8).base64EncodedString(),
            Data("img-three".utf8).base64EncodedString()
        ]
        for i in 0..<3 {
            let dict = try XCTUnwrap(content[i + 1]["image_url"] as? [String: Any])
            XCTAssertEqual(content[i + 1]["type"] as? String, "image_url")
            let url = dict["url"] as? String ?? ""
            XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
            XCTAssertTrue(url.contains(expectedPayloads[i]),
                "第 \(i + 1) 张图内容错位：期望包含 \(expectedPayloads[i])")
            XCTAssertEqual(dict["detail"] as? String, "low",
                "远程 host 第 \(i + 1) 张图应带 detail: low")
        }
    }

    /// 本地 host 五种变体（localhost / 127.0.0.1 / 192.168.x / 10.x / .local）：
    /// 多图消息里 detail 必须**逐张**剥离，一张都不能漏。
    func testChatVision_localHostFiveVariants_stripsDetailPerImage() async throws {
        let hosts = [
            "http://localhost:1234/v1",
            "http://127.0.0.1:1234/v1",
            "http://192.168.31.7:1234/v1",
            "http://10.0.0.8:1234/v1",
            "http://study-mac.local:1234/v1"
        ]
        for host in hosts {
            let box = JSONBox()
            AdvStubProtocol.responder = { request in
                let body = request.advHttpBodyData ?? Data()
                box.set(try! JSONSerialization.jsonObject(with: body) as! [String: Any])
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(advFrameOKBody.utf8))
            }
            let service = OpenAICompatibleService(
                baseURL: URL(string: host)!,
                model: "qwen", apiKey: "k", session: advStubSession()
            )
            _ = try await service.chatVision(
                system: "s", user: "u",
                imagesJPEG: [Data("a".utf8), Data("b".utf8)],
                temperature: 0.3
            )
            let json = try XCTUnwrap(box.value, "\(host)：应抓到请求体")
            let messages = json["messages"] as! [[String: Any]]
            let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]], "\(host)")
            XCTAssertEqual(content.count, 3, "\(host)：2 张图 → text + 2 image_url")
            for i in 1..<content.count {
                let dict = try XCTUnwrap(content[i]["image_url"] as? [String: Any], "\(host)")
                XCTAssertNil(dict["detail"], "\(host)：第 \(i) 张图 detail 应被剥离（本地 host）")
            }
        }
    }

    /// IPv6 loopback（[::1]）不在 isLocalHost 白名单 → 按远程处理、detail 保留。
    /// 锚点记录实际行为：若本地 VLM 严格校验 detail 字段，[::1] 部署会受影响——报 lead 知悉。
    func testChatVision_ipv6Loopback_treatedAsRemote_documented() async throws {
        let box = JSONBox()
        AdvStubProtocol.responder = { request in
            let body = request.advHttpBodyData ?? Data()
            box.set(try! JSONSerialization.jsonObject(with: body) as! [String: Any])
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(advFrameOKBody.utf8))
        }
        let service = OpenAICompatibleService(
            baseURL: URL(string: "http://[::1]:1234/v1")!,
            model: "qwen", apiKey: "k", session: advStubSession()
        )
        _ = try await service.chatVision(
            system: "s", user: "u", imagesJPEG: [Data("a".utf8)], temperature: 0.3
        )
        let json = try XCTUnwrap(box.value)
        let messages = json["messages"] as! [[String: Any]]
        let content = messages[1]["content"] as! [[String: Any]]
        let dict = content[1]["image_url"] as! [String: Any]
        XCTAssertEqual(dict["detail"] as? String, "low",
            "[::1] 当前按远程处理（isLocalHost 未覆盖 IPv6 loopback）——行为锚点")
    }

    /// chatVision 直接传空数组（API 误用，生产路径 analyzeFrame 会分流到 chatText）：
    /// 不崩，content 退化为仅 text 的数组形态。锚点。
    func testChatVision_emptyImagesArray_sendsTextOnlyContentArray_documented() async throws {
        let box = JSONBox()
        AdvStubProtocol.responder = { request in
            let body = request.advHttpBodyData ?? Data()
            box.set(try! JSONSerialization.jsonObject(with: body) as! [String: Any])
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(advFrameOKBody.utf8))
        }
        let service = OpenAICompatibleService(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            model: "gpt-4o-mini", apiKey: "k", session: advStubSession()
        )
        _ = try await service.chatVision(system: "s", user: "u", imagesJPEG: [], temperature: 0.3)
        let json = try XCTUnwrap(box.value)
        let messages = json["messages"] as! [[String: Any]]
        let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1, "空图数组 → content 只剩 text 一项（数组形态）")
        XCTAssertEqual(content[0]["type"] as? String, "text")
    }

    // MARK: - 任务 8：prompt 一致性

    /// screenshotCount = 1（含省略参数走默认值）→ 无多屏说明段。回归锚点：单屏 prompt 不得漂移。
    func testAnalyzeFrameUser_countOne_noMultiScreenSegment() {
        for text in [
            PromptTemplates.analyzeFrameUser(promise: "写代码", appName: "Xcode", windowTitles: "a.swift"),
            PromptTemplates.analyzeFrameUser(promise: "写代码", appName: "Xcode", windowTitles: "a.swift", screenshotCount: 1)
        ] {
            XCTAssertFalse(text.contains("张截图"), "screenshotCount=1 不应出现多屏说明段：\(text)")
            XCTAssertFalse(text.contains("显示器"), "screenshotCount=1 不应提到显示器：\(text)")
        }
    }

    /// screenshotCount = 0（纯文本路径实际不会带图）→ 同样无说明段（0 不应触发 >1 分支）。
    func testAnalyzeFrameUser_countZero_noMultiScreenSegment() {
        let text = PromptTemplates.analyzeFrameUser(
            promise: "写代码", appName: "Xcode", windowTitles: "a.swift", screenshotCount: 0
        )
        XCTAssertFalse(text.contains("张截图"), "screenshotCount=0 不应出现多屏说明段")
    }

    /// screenshotCount = 3 → 说明段存在且 N 正确（不是硬编码的 2）。
    func testAnalyzeFrameUser_countThree_segmentWithCorrectN() {
        let text = PromptTemplates.analyzeFrameUser(
            promise: "写代码", appName: "Xcode", windowTitles: "a.swift", screenshotCount: 3
        )
        XCTAssertTrue(text.contains("附 3 张截图，对应 3 块显示器"),
            "说明段应带正确的 N=3：\(text)")
        XCTAssertTrue(text.contains("从左到右"), "说明段应声明排列顺序：\(text)")
    }

    /// 端到端：analyzeFrame 的 prompt 说明段数量与**实际附图数**自洽。
    /// 这是"部分屏编码失败 → jpegs 变少 → prompt 同步变少"自洽链路的最后一环。
    func testAnalyzeFrame_endToEnd_promptNoteMatchesAttachedImageCount() async throws {
        let texts = TextBox()
        AdvStubProtocol.responder = { request in
            let body = request.advHttpBodyData ?? Data()
            let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            let messages = json["messages"] as! [[String: Any]]
            let content = messages[1]["content"] as! [[String: Any]]
            texts.append(content[0]["text"] as! String)
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(advFrameOKBody.utf8))
        }
        let service = OpenAICompatibleService(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            model: "gpt-4o-mini", apiKey: "k", session: advStubSession()
        )

        // 2 张图 → 说明段带 N=2
        _ = try await service.analyzeFrame(FrameAnalysisInput(
            promise: "写代码", appName: "Xcode", windowTitles: "a.swift",
            screenshotJPEGs: [Data("x".utf8), Data("y".utf8)]
        ))
        // 1 张图（如部分屏编码失败后）→ 无说明段
        _ = try await service.analyzeFrame(FrameAnalysisInput(
            promise: "写代码", appName: "Xcode", windowTitles: "a.swift",
            screenshotJPEGs: [Data("x".utf8)]
        ))

        let captured = texts.values
        XCTAssertEqual(captured.count, 2)
        XCTAssertTrue(captured[0].contains("附 2 张截图，对应 2 块显示器"),
            "2 张图时 prompt 应有 N=2 说明段：\(captured[0])")
        XCTAssertFalse(captured[1].contains("张截图"),
            "1 张图时 prompt 不应有多屏说明段：\(captured[1])")
    }
}

// MARK: - SwiftData 链路（任务 3）

/// persistTick 第一张写失败仍入库 relative 的链路自洽性：
/// 生产路径（persistTick 私有，无法直接驱动）拆成可测的两层——
/// SwiftData 落 record（带 screenshotLocalPath）+ ScreenshotStore 读取侧降级。
@MainActor
final class MultiDisplayPersistChainTests: XCTestCase {

    /// record 带 screenshotLocalPath 入库但盘上无文件（第一张写失败）：
    /// 读取侧 existingScreenshotURLs 返回空 → UI 走无截图分支，字段无损，链路自洽不崩。
    func testPersistedRecord_missingScreenshotFile_readSideDegradesGracefully() throws {
        let container = AppContainer.inMemory()
        let ctx = container.mainContext
        let session = FocusSession(promise: "链路自洽", plannedDuration: 1500)
        ctx.insert(session)
        // 幽灵路径：session 目录从未创建（不经过 newScreenshotURL），文件必不存在
        let ghost = "\(session.id.uuidString)/20990101_000000000.jpg"
        let rec = AnalysisRecord(
            session: session,
            screenshotLocalPath: ghost,
            frontAppName: "Xcode", frontWindowTitles: "main.swift",
            level: .fully, reasoning: "写码", reminder: "",
            fromAI: true, hasChanged: false,
            dhashHex: "abcd", dhashDistance: 12
        )
        ctx.insert(rec)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<AnalysisRecord>())
        let r = try XCTUnwrap(fetched.first)
        XCTAssertEqual(r.screenshotLocalPath, ghost, "relative 应照常入库（persistTick 无条件赋值）")
        XCTAssertEqual(r.dhashHex, "abcd")
        XCTAssertEqual(r.dhashDistance, 12)

        let urls = ScreenshotStore.existingScreenshotURLs(relativePath: r.screenshotLocalPath!)
        XCTAssertTrue(urls.isEmpty,
            "第一张缺失 → 读取侧空数组 → SessionDetailView 走无截图灰块分支，不崩")
    }
}

// MARK: - 测试替身

/// stub 统一返回的合法 FrameAnalysis 响应体（chatVision 只取 content 字符串，analyzeFrame 再解码）。
private let advFrameOKBody =
    #"{"choices":[{"message":{"content":"{\"level\":\"fully\",\"reasoning\":\"ok\",\"reminder\":\"\"}"}}]}"#

/// 记录每次 analyzeFrame 入参的 mock（验证 AI 实际收到几张图）。
actor RecordingAIService: AIService {
    private let level: FocusLevel
    private(set) var frameInputs: [FrameAnalysisInput] = []
    var callCount: Int { frameInputs.count }
    var firstFrameInput: FrameAnalysisInput? { frameInputs.first }

    init(level: FocusLevel) { self.level = level }

    func analyzeTask(_ promise: String) async throws -> TaskAnalysis {
        TaskAnalysis(taskType: .other, suggestion: nil)
    }

    func analyzeFrame(_ input: FrameAnalysisInput) async throws -> FrameAnalysis {
        frameInputs.append(input)
        return FrameAnalysis(level: level, reasoning: "recording mock", reminder: "")
    }

    func summarize(_ input: SummaryInput) async throws -> String { "recording summary" }
}

/// 带闸门的 recording mock：hold 期间 analyzeFrame 挂起，用于确定性构造"AI 在飞"时序。
actor GatedRecordingAIService: AIService {
    private let level: FocusLevel
    private(set) var frameInputs: [FrameAnalysisInput] = []
    private var holdCalls = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var callCount: Int { frameInputs.count }

    init(level: FocusLevel) { self.level = level }

    func setHold(_ hold: Bool) {
        holdCalls = hold
        if !hold {
            let ws = waiters
            waiters.removeAll()
            ws.forEach { $0.resume() }
        }
    }

    func analyzeTask(_ promise: String) async throws -> TaskAnalysis {
        TaskAnalysis(taskType: .other, suggestion: nil)
    }

    func analyzeFrame(_ input: FrameAnalysisInput) async throws -> FrameAnalysis {
        frameInputs.append(input)
        if holdCalls {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                waiters.append(c)
            }
        }
        return FrameAnalysis(level: level, reasoning: "gated mock", reminder: "")
    }

    func summarize(_ input: SummaryInput) async throws -> String { "gated summary" }
}

/// 独立命名的 URLProtocol stub（避免与既有测试文件的 private stub 冲突）。
private final class AdvStubProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (resp, data) = responder(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 线程安全的请求体收集盒（URLProtocol 回调在后台线程）。
private final class JSONBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: [String: Any]?
    func set(_ v: [String: Any]) { lock.lock(); _value = v; lock.unlock() }
    var value: [String: Any]? { lock.lock(); defer { lock.unlock() }; return _value }
}

private final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    func append(_ s: String) { lock.lock(); _values.append(s); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return _values }
}

private extension URLRequest {
    /// URLProtocol 下 httpBody 经 bodyStream 暴露（与既有测试同款读取法）。
    var advHttpBodyData: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buf, maxLength: buf.count)
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return data
    }
}
