import Foundation
import CoreImage
import CoreGraphics

/// 16x16 灰度差分哈希（256 bit）。
/// 算法：缩放到 17x16 → 灰度化 → 每行内相邻像素比较 → 16 行 × 16 bit = 256 bit。
///
/// 经验距离参考（256 bit 下汉明距离）：
/// - 0~15  几乎不动
/// - 15~30 小变化（滚动、光标移动）
/// - 30~60 明显变化（切 tab、切段落）
/// - 60~  大变化（切 app）
enum DHashComputer {

    static let bits = 256  // 16 * 16
    static let width = 17  // 多一列做横向差分
    static let height = 16

    /// 计算 dHash，返回 32 字节（256 bit）。
    static func hash(_ image: CGImage) -> Data {
        guard let gray = grayscalePixels(image) else {
            return Data(repeating: 0, count: 32)
        }
        var bits = [UInt8](repeating: 0, count: 32)
        for row in 0..<height {
            for col in 0..<(width - 1) {
                let left = gray[row * width + col]
                let right = gray[row * width + col + 1]
                if left > right {
                    let bitIdx = row * (width - 1) + col
                    bits[bitIdx / 8] |= (1 << (7 - bitIdx % 8))
                }
            }
        }
        return Data(bits)
    }

    /// 汉明距离。两个哈希长度不等返回 Int.max。
    static func distance(_ a: Data, _ b: Data) -> Int {
        guard a.count == b.count else { return .max }
        var dist = 0
        for i in 0..<a.count {
            dist += (a[i] ^ b[i]).nonzeroBitCount
        }
        return dist
    }

    /// 把 CGImage 缩放到 17x16 灰度，返回 272 字节像素数组（每个 0~255）。
    private static func grayscalePixels(_ image: CGImage) -> [UInt8]? {
        let space = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}

extension Data {
    /// 16 进制字符串表示（小写）。用于日志和持久化。
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
