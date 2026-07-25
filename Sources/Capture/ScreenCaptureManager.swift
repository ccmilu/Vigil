import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreImage
import AppKit
import ImageIO
import UniformTypeIdentifiers
import OSLog

/// 一块显示器的截屏帧。displayID 与 SCDisplay.displayID 同源（CGDirectDisplayID）。
/// 数组顺序约定：按物理位置从左到右（SCDisplay.frame.minX 升序），
/// 此排序是全链路唯一顺序来源（AI 多图顺序、后续 _pN 落盘顺序）。
struct DisplayFrame: Sendable {
    let displayID: CGDirectDisplayID
    let image: CGImage
}

extension Array where Element == DisplayFrame {
    /// 取主屏帧：优先 displayID == CGMainDisplayID()，取不到退 frames[0]。空数组返回 nil。
    /// 多屏改造过渡期内，下游（AI 输入 / 落盘）统一经此取主屏，保证单屏行为与旧版一致。
    func mainDisplayFrame() -> DisplayFrame? {
        if let main = first(where: { $0.displayID == CGMainDisplayID() }) {
            return main
        }
        return first
    }
}

/// 抓显示器并按长边 1660 等比缩放、JPEG quality 0.75 写入指定路径。
/// 通过 ScreenCaptureKit 实现（macOS 14+）。
@MainActor
final class ScreenCaptureManager {

    enum CaptureError: LocalizedError {
        case noDisplay
        case captureFailed(String)
        case encodeFailed
        case writeFailed(String)
        case desktopOnly  // 仅看到桌面，被上层 skip

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "没有可用显示器"
            case .captureFailed(let m): return "截屏失败：\(m)"
            case .encodeFailed: return "JPEG 编码失败"
            case .writeFailed(let m): return "写盘失败：\(m)"
            case .desktopOnly: return "当前仅桌面可见，已跳过"
            }
        }
    }

    // 编码常量：nonisolated 让 jpegData/downscale（nonisolated static）可直接引用
    nonisolated static let maxLongEdge: CGFloat = 1660
    nonisolated static let jpegQuality: CGFloat = 0.75

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Vigil", category: "ScreenCaptureManager")

    /// 抓全部显示器，每屏各一张，按物理从左到右（frame.minX 升序）排列。
    /// SCShareableContent 只取一次；desktopOnly 全局窗口判定保留（任一非自家窗口即放行）。
    /// 每屏独立 SCContentFilter + SCScreenshotManager 串行截屏：
    /// 单屏失败只记 OSLog 跳过，不中断其他屏；全部失败才抛错。
    func captureAllDisplays() async throws -> [DisplayFrame] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        guard !content.displays.isEmpty else {
            throw CaptureError.noDisplay
        }
        // 至少有一个非自家窗口（避免只截到自己）
        let interestingWindows = content.windows.filter { win in
            guard let owner = win.owningApplication else { return false }
            return owner.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        if interestingWindows.isEmpty {
            throw CaptureError.desktopOnly
        }

        // minX 升序 = 物理从左到右（AI 多图顺序与落盘顺序的唯一来源）
        let displays = content.displays.sorted { $0.frame.minX < $1.frame.minX }

        var frames: [DisplayFrame] = []
        for display in displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            config.capturesAudio = false
            config.scalesToFit = true
            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                frames.append(DisplayFrame(displayID: display.displayID, image: image))
            } catch {
                // 单屏失败跳过，其余屏照常
                logger.warning("显示器 \(display.displayID) 截屏失败，已跳过：\(error.localizedDescription)")
            }
        }
        guard !frames.isEmpty else {
            throw CaptureError.captureFailed("所有显示器截屏均失败")
        }
        return frames
    }

    /// 抓主屏一张截图，返回 CGImage（不写盘）。上层决定是否落盘。
    /// 便捷壳：基于 captureAllDisplays，优先 displayID == CGMainDisplayID()，取不到退 frames[0]。
    /// 签名保持不变，Settings 连通性测试等旧调用方零改动。
    func captureMainDisplay() async throws -> CGImage {
        let frames = try await captureAllDisplays()
        guard let main = frames.mainDisplayFrame() else {
            throw CaptureError.noDisplay
        }
        return main.image
    }

    /// 把 CGImage 压缩并写入 url。薄壳：jpegData 编码 + 写盘。
    func encodeAndWrite(_ image: CGImage, to url: URL) throws {
        let data = try Self.jpegData(image)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CaptureError.writeFailed(error.localizedDescription)
        }
    }

    /// 把 CGImage 按长边 1660 等比缩放后编码为 JPEG（quality 0.75），直接返回 Data，不写临时文件。
    /// nonisolated：纯 CPU 编码不触碰实例状态，供 actor（FrameAnalyzer）与任意上下文直接调用，
    /// 消除每帧每屏一次"临时文件 + MainActor 跳转"的 IO 环路。
    nonisolated static func jpegData(_ image: CGImage) throws -> Data {
        let scaled = downscale(image, longEdge: maxLongEdge)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else {
            throw CaptureError.encodeFailed
        }
        CGImageDestinationAddImage(dest, scaled, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw CaptureError.encodeFailed
        }
        return data as Data
    }

    /// 长边缩到 maxEdge 的等比缩放。若已小于不缩。
    nonisolated static func downscale(_ image: CGImage, longEdge: CGFloat) -> CGImage {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let maxSide = max(w, h)
        guard maxSide > longEdge else { return image }
        let scale = longEdge / maxSide
        let newW = Int(w * scale)
        let newH = Int(h * scale)

        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = newW * 4
        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }
}

// MARK: - 存储路径辅助

enum ScreenshotStore {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Vigil", category: "ScreenshotStore")

    /// Application Support/Vigil/Screenshots/
    ///
    /// 降级策略：若 Application Support 目录获取或创建失败（沙盒异常、磁盘只读、权限缺失），
    /// 自动降级到 `tmp/Vigil/Screenshots`，并通过 OSLog 记录警告。
    /// 降级到 tmp 后截图不会持久化（重启后丢失），但至少不会 fatalError 崩溃。
    /// v0.2 计划用 Security-Scoped Bookmark 彻底解决写权限问题。
    static var rootDirectory: URL {
        let base: URL
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            base = appSupport.appendingPathComponent("Vigil/Screenshots", isDirectory: true)
        } catch {
            // Application Support 目录不可用，降级到临时目录
            logger.warning("无法获取 Application Support 目录，降级到临时目录。error=\(error.localizedDescription)")
            base = FileManager.default.temporaryDirectory
                .appendingPathComponent("Vigil/Screenshots", isDirectory: true)
        }
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    /// 生成相对路径 `<sessionUUID>/<YYYYMMDD>_<HHMMSSmmm>.jpg`。
    static func newScreenshotURL(sessionID: UUID, at date: Date = .now) -> (URL, String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        let name = formatter.string(from: date) + ".jpg"
        let dir = rootDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let full = dir.appendingPathComponent(name)
        let relative = "\(sessionID.uuidString)/\(name)"
        return (full, relative)
    }

    /// 第 N 屏（N≥2）截图的推导命名：与第一张同目录，去扩展名 + `_pN.jpg`。
    /// 只写盘不入库——schema 零迁移的核心约定，读写两侧都集中在 ScreenshotStore 内。
    static func siblingScreenshotURL(firstURL: URL, index: Int) -> URL {
        precondition(index >= 2, "sibling 序号从 2 开始（第一张走 newScreenshotURL）")
        let dir = firstURL.deletingLastPathComponent()
        let stem = firstURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(stem)_p\(index).jpg")
    }

    /// 读取侧：给定入库的 screenshotLocalPath（第一张的相对路径），返回实际存在的全部帧截图
    /// （第一张 + 连续 _p2/_p3...，断号即停——容忍 Finder 手动删图造成的空洞）。
    /// 第一张不存在返回空数组；旧单屏数据天然返回单元素数组。
    /// R2 输入防御：空串 / 绝对路径 / 含 ".." 路径穿越 → 一律返回空（旧行为会把
    /// rootDirectory 自身或父目录当"第一张"返回）。生产 relative 只由 newScreenshotURL
    /// 生成（"UUID/时间戳.jpg"），此防御面向未来外部输入。
    static func existingScreenshotURLs(relativePath: String) -> [URL] {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            return []
        }
        let first = rootDirectory.appendingPathComponent(relativePath)
        let fm = FileManager.default
        guard fm.fileExists(atPath: first.path) else { return [] }
        var urls = [first]
        var index = 2
        while true {
            let sibling = siblingScreenshotURL(firstURL: first, index: index)
            guard fm.fileExists(atPath: sibling.path) else { break }
            urls.append(sibling)
            index += 1
        }
        return urls
    }
}
