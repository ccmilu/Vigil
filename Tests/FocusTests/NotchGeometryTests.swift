import XCTest
@testable import Focus

/// 验证 NotchTimer.islandGeometry 的 single source 行为：
/// 折叠 / 展开尺寸与 NotchStyle 参数一致，且 currentIslandRect 与 geometry 保持对齐。
///
/// 注意：ScreenMetrics 读 NSScreen.main，XCTest 进程无显示器时返回 nil 会走回退值。
/// autoDetect=true 路径下的公式测试依赖回退值（notchWidth=220 / menuBarHeight=24），
/// 这在 CI 无头环境里同样成立。
@MainActor
final class NotchGeometryTests: XCTestCase {

    // MARK: - 展开态高度始终等于 expandedHeight（autoDetect 无影响）

    func testExpandedHeightAlwaysFromStyle() {
        let geo = NotchTimer.shared.islandGeometry
        XCTAssertEqual(geo.expanded.height, NotchStyle.expandedHeight, accuracy: 0.01,
                       "展开态高度必须与 NotchStyle.expandedHeight 一致，autoDetect 不影响此值")
    }

    // MARK: - 尺寸合理性（无论 autoDetect 开关，都应大于 0）

    func testGeometrySizesArePositive() {
        let geo = NotchTimer.shared.islandGeometry
        XCTAssertGreaterThan(geo.collapsed.width,  0, "折叠态宽度应 > 0")
        XCTAssertGreaterThan(geo.collapsed.height, 0, "折叠态高度应 > 0")
        XCTAssertGreaterThan(geo.expanded.width,   0, "展开态宽度应 > 0")
        XCTAssertGreaterThan(geo.expanded.height,  0, "展开态高度应 > 0")
    }

    // MARK: - autoDetect=true 路径：展开态宽 = notchWidth + 2×expandedSideExtension

    func testAutoDetectExpandedWidthFormula() {
        guard NotchStyle.autoDetect else { return }
        let geo = NotchTimer.shared.islandGeometry
        // ScreenMetrics.notchWidth 在无显示器时返回 220（回退值）
        let expected = ScreenMetrics.notchWidth + 2 * NotchStyle.expandedSideExtension
        XCTAssertEqual(geo.expanded.width, expected, accuracy: 0.01,
                       "autoDetect 展开态宽度公式：notchWidth + 2×expandedSideExtension")
    }

    // MARK: - autoDetect=true 路径：折叠态宽 = sidePad×2 + levelIconSize + notchWidth + middleExtra + progressRingSize

    func testAutoDetectCollapsedWidthFormula() {
        guard NotchStyle.autoDetect else { return }
        let geo = NotchTimer.shared.islandGeometry
        let sidePad = max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6
        let expected = sidePad + NotchStyle.levelIconSize
                     + (ScreenMetrics.notchWidth + NotchStyle.collapsedMiddleExtra)
                     + NotchStyle.progressRingSize + sidePad
        XCTAssertEqual(geo.collapsed.width, expected, accuracy: 0.01,
                       "autoDetect 折叠态宽度公式与 islandGeometry 不符")
    }

    // MARK: - autoDetect=false 路径：直接等于 manualXxx 常量

    func testManualSizesWhenAutoDetectOff() {
        guard !NotchStyle.autoDetect else { return }
        let geo = NotchTimer.shared.islandGeometry
        XCTAssertEqual(geo.collapsed.width,  NotchStyle.manualCollapsedWidth,  accuracy: 0.01)
        XCTAssertEqual(geo.collapsed.height, NotchStyle.manualCollapsedHeight, accuracy: 0.01)
        XCTAssertEqual(geo.expanded.width,   NotchStyle.manualExpandedWidth,   accuracy: 0.01)
    }

    // MARK: - currentIslandRect 展开态宽高与 geometry.expanded 一致

    /// 验证 currentIslandRect（展开态）的 width/height 与 islandGeometry.expanded 完全一致。
    func testCurrentIslandRectExpandedMatchesGeometry() {
        let timer = NotchTimer.shared
        // 强制展开态
        timer.forceExpandUntil = Date().addingTimeInterval(60)
        defer { timer.forceExpandUntil = nil }

        let geo = timer.islandGeometry
        // 用一个足够大的 panelSize 避免 x 算出负数
        let panelSize = NSSize(width: geo.expanded.width + 200, height: geo.expanded.height + 100)
        let rect = timer.currentIslandRect(in: panelSize, isFlipped: true)

        XCTAssertEqual(rect.width,  geo.expanded.width,  accuracy: 0.01,
                       "currentIslandRect 展开态宽度应与 geometry.expanded.width 一致")
        XCTAssertEqual(rect.height, geo.expanded.height, accuracy: 0.01,
                       "currentIslandRect 展开态高度应与 geometry.expanded.height 一致")
    }

    // MARK: - currentIslandRect 折叠态宽高与 geometry.collapsed 一致

    func testCurrentIslandRectCollapsedMatchesGeometry() {
        let timer = NotchTimer.shared
        // 确保没有强制展开
        timer.forceExpandUntil = nil
        timer.hovering = false

        let geo = timer.islandGeometry
        let panelSize = NSSize(width: geo.expanded.width + 200, height: geo.expanded.height + 100)
        let rect = timer.currentIslandRect(in: panelSize, isFlipped: true)

        XCTAssertEqual(rect.width,  geo.collapsed.width,  accuracy: 0.01,
                       "currentIslandRect 折叠态宽度应与 geometry.collapsed.width 一致")
        XCTAssertEqual(rect.height, geo.collapsed.height, accuracy: 0.01,
                       "currentIslandRect 折叠态高度应与 geometry.collapsed.height 一致")
    }

    // MARK: - currentIslandRect 水平居中

    func testCurrentIslandRectCenteredHorizontally() {
        let timer = NotchTimer.shared
        timer.forceExpandUntil = nil
        timer.hovering = false

        let geo = timer.islandGeometry
        let panelW: CGFloat = geo.expanded.width + 200
        let panelSize = NSSize(width: panelW, height: geo.expanded.height + 100)
        let rect = timer.currentIslandRect(in: panelSize, isFlipped: true)

        let expectedX = (panelW - geo.collapsed.width) / 2
        XCTAssertEqual(rect.minX, expectedX, accuracy: 0.01,
                       "折叠态岛应在 panel 中水平居中")
    }
}
