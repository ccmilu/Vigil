import XCTest
import CoreGraphics
@testable import Vigil

final class DHashComputerTests: XCTestCase {

    /// 给定颜色单色图，dHash 应稳定（无随机性）
    func testSameImageZeroDistance() {
        let img = Self.solidImage(width: 200, height: 100, gray: 128)
        let h1 = DHashComputer.hash(img)
        let h2 = DHashComputer.hash(img)
        XCTAssertEqual(h1.count, 32)
        XCTAssertEqual(DHashComputer.distance(h1, h2), 0)
    }

    /// 渐变图与反色渐变图应有非零汉明距离
    func testGradientVsInverseGradientLargeDistance() {
        let a = Self.gradientImage(width: 200, height: 100, reversed: false)
        let b = Self.gradientImage(width: 200, height: 100, reversed: true)
        let ha = DHashComputer.hash(a)
        let hb = DHashComputer.hash(b)
        let dist = DHashComputer.distance(ha, hb)
        XCTAssertGreaterThan(dist, 50, "反色渐变距离应明显，实际 \(dist)")
    }

    /// 同图微小亮度抖动距离应小
    func testTinyShiftSmallDistance() {
        let a = Self.gradientImage(width: 200, height: 100, reversed: false)
        let b = Self.gradientImage(width: 200, height: 100, reversed: false, brightnessOffset: 5)
        let dist = DHashComputer.distance(DHashComputer.hash(a), DHashComputer.hash(b))
        XCTAssertLessThan(dist, 20, "亮度+5 距离应小，实际 \(dist)")
    }

    func testHexStringRoundtrip() {
        let data = Data([0x00, 0xff, 0xab, 0xcd])
        XCTAssertEqual(data.hexString, "00ffabcd")
    }

    // MARK: - Helpers

    /// 单色灰度图
    static func solidImage(width: Int, height: Int, gray: UInt8) -> CGImage {
        let space = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width, space: space,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        ctx.setFillColor(gray: CGFloat(gray) / 255.0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// 横向渐变灰度图，reversed=true 反向；brightnessOffset 可整体加亮度。
    static func gradientImage(width: Int, height: Int, reversed: Bool, brightnessOffset: Int = 0) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var v = Int(Double(x) / Double(width - 1) * 255.0)
                if reversed { v = 255 - v }
                v = max(0, min(255, v + brightnessOffset))
                pixels[y * width + x] = UInt8(v)
            }
        }
        let space = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width, space: space,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return ctx.makeImage()!
    }
}
