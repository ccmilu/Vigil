import XCTest
@testable import Vigil

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

    // MARK: - autoDetect=true 路径：展开态宽跟随主屏实际形态

    /// 兼容壳 `compute(for: .main)` 的公式选择逻辑（与生产代码逐项镜像）：
    /// 无头（main=nil）强制走有刘海回退；有屏时按该屏是否真有刘海选公式。
    /// 测试机主屏换成无刘海外接显示器时（热插拔场景），断言也必须跟着换公式。
    private var mainScreenUsesNotchFormula: Bool {
        guard let main = NSScreen.main else { return true }  // 无头：compute(for:nil) 强制有刘海
        return ScreenMetrics.hasNotchedDisplay(for: main)
    }

    func testAutoDetectExpandedWidthFormula() {
        guard NotchStyle.autoDetect else { return }
        let geo = NotchTimer.shared.islandGeometry
        let expected: CGFloat
        if mainScreenUsesNotchFormula {
            // 有刘海 / 无头回退：notchWidth + 2×expandedSideExtension（无头时 notchWidth=220）
            expected = ScreenMetrics.notchWidth + 2 * NotchStyle.expandedSideExtension
        } else {
            // 无刘海主屏（如外接显示器为主屏）：2×ext + compactGap
            expected = 2 * NotchStyle.expandedSideExtension + NotchStyle.collapsedCompactGap
        }
        XCTAssertEqual(geo.expanded.width, expected, accuracy: 0.01,
                       "autoDetect 展开态宽度公式应跟随主屏是否有刘海")
    }

    // MARK: - autoDetect=true 路径：折叠态宽跟随主屏实际形态

    func testAutoDetectCollapsedWidthFormula() {
        guard NotchStyle.autoDetect else { return }
        let geo = NotchTimer.shared.islandGeometry
        let sidePad = max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6
        let expected: CGFloat
        if mainScreenUsesNotchFormula {
            expected = sidePad + NotchStyle.levelIconSize
                     + (ScreenMetrics.notchWidth + NotchStyle.collapsedMiddleExtra)
                     + NotchStyle.progressRingSize + sidePad
        } else {
            expected = sidePad + NotchStyle.levelIconSize
                     + NotchStyle.collapsedCompactGap
                     + NotchStyle.progressRingSize + sidePad
        }
        XCTAssertEqual(geo.collapsed.width, expected, accuracy: 0.01,
                       "autoDetect 折叠态宽度公式应跟随主屏是否有刘海")
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

    // MARK: - 无刘海屏：compute(hasNotch:false) 紧凑公式（多显示器改造新增）

    /// 无刘海折叠态宽 = sidePad×2 + levelIconSize + compactGap + progressRingSize
    func testNoNotchCollapsedWidthFormula() {
        guard NotchStyle.autoDetect else { return }
        let geo = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 24)
        let sidePad = max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6
        let expected = sidePad + NotchStyle.levelIconSize
                     + NotchStyle.collapsedCompactGap
                     + NotchStyle.progressRingSize + sidePad
        XCTAssertEqual(geo.collapsed.width, expected, accuracy: 0.01,
                       "无刘海折叠态宽度公式：sidePad×2 + icon + compactGap + ring")
        XCTAssertFalse(geo.hasNotch, "hasNotch 字段应原样保留入参")
    }

    /// 无刘海展开态宽 = 2×expandedSideExtension + compactGap
    func testNoNotchExpandedWidthFormula() {
        guard NotchStyle.autoDetect else { return }
        let geo = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 24)
        let expected = 2 * NotchStyle.expandedSideExtension + NotchStyle.collapsedCompactGap
        XCTAssertEqual(geo.expanded.width, expected, accuracy: 0.01,
                       "无刘海展开态宽度公式：2×ext + compactGap")
    }

    /// 有刘海分支与改版前 islandGeometry 逐项相等（回归锚点）
    func testHasNotchFormulasMatchLegacy() {
        guard NotchStyle.autoDetect else { return }
        let geo = IslandGeometry.compute(hasNotch: true, notchWidth: 220, menuBarHeight: 24)
        let sidePad = max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6
        XCTAssertEqual(geo.collapsed.width,
                       sidePad + NotchStyle.levelIconSize
                       + (220 + NotchStyle.collapsedMiddleExtra)
                       + NotchStyle.progressRingSize + sidePad,
                       accuracy: 0.01, "有刘海折叠态宽度公式不得漂移")
        XCTAssertEqual(geo.expanded.width, 220 + 2 * NotchStyle.expandedSideExtension,
                       accuracy: 0.01, "有刘海展开态宽度公式不得漂移")
        XCTAssertEqual(geo.collapsed.height, 24, accuracy: 0.01,
                       "折叠态高度 = 菜单栏高度")
        XCTAssertEqual(geo.expanded.height, NotchStyle.expandedHeight, accuracy: 0.01)
    }

    /// 无菜单栏的副屏（menuBarHeight=0 的罕见配置）折叠态高度回退 24，不出现 0 高岛
    func testCollapsedHeightFallbackWhenNoMenuBar() {
        guard NotchStyle.autoDetect else { return }
        let geo = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 0)
        XCTAssertEqual(geo.collapsed.height, 24, accuracy: 0.01,
                       "menuBarHeight=0 时折叠态高度应回退 24")
    }

    /// islandRect 纯函数：展开 / 折叠宽高与 geometry 一致、水平居中
    func testIslandRectPureFunction() {
        let geo = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 24)
        let panelSize = NSSize(width: geo.expanded.width + 200, height: geo.expanded.height + 100)

        let expandedRect = geo.islandRect(isExpanded: true, in: panelSize, isFlipped: true)
        XCTAssertEqual(expandedRect.width, geo.expanded.width, accuracy: 0.01)
        XCTAssertEqual(expandedRect.height, geo.expanded.height, accuracy: 0.01)
        XCTAssertEqual(expandedRect.minX, (panelSize.width - geo.expanded.width) / 2, accuracy: 0.01)

        let collapsedRect = geo.islandRect(isExpanded: false, in: panelSize, isFlipped: true)
        XCTAssertEqual(collapsedRect.width, geo.collapsed.width, accuracy: 0.01)
        XCTAssertEqual(collapsedRect.height, geo.collapsed.height, accuracy: 0.01)

        // isFlipped=false（y 向上）：岛贴 panel 顶 → y = panelH - islandH
        let flippedRect = geo.islandRect(isExpanded: false, in: panelSize, isFlipped: false)
        XCTAssertEqual(flippedRect.minY, panelSize.height - geo.collapsed.height, accuracy: 0.01)
    }
}
