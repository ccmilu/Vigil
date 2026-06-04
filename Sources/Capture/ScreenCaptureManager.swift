import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreImage
import AppKit
import ImageIO
import UniformTypeIdentifiers
import OSLog

/// 抓主屏并按长边 1660 等比缩放、JPEG quality 0.75 写入指定路径。
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

    static let maxLongEdge: CGFloat = 1660
    static let jpegQuality: CGFloat = 0.75

    /// 抓一张截图，返回 CGImage（不写盘）。上层决定是否落盘。
    func captureMainDisplay() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
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
            return image
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    /// 把 CGImage 压缩并写入 url。
    func encodeAndWrite(_ image: CGImage, to url: URL) throws {
        let scaled = Self.downscale(image, longEdge: Self.maxLongEdge)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else {
            throw CaptureError.encodeFailed
        }
        CGImageDestinationAddImage(dest, scaled, [
            kCGImageDestinationLossyCompressionQuality: Self.jpegQuality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw CaptureError.encodeFailed
        }
        do {
            try (data as Data).write(to: url, options: .atomic)
        } catch {
            throw CaptureError.writeFailed(error.localizedDescription)
        }
    }

    /// 长边缩到 maxEdge 的等比缩放。若已小于不缩。
    static func downscale(_ image: CGImage, longEdge: CGFloat) -> CGImage {
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
}
