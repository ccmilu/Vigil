import XCTest
@testable import Vigil

/// IslandGeometry 边界与锚点测试（多显示器改造的纯函数部分，CI 可测，不读 NSScreen）。
///
/// 与 NotchGeometryTests 的分工：
/// - NotchGeometryTests 用**符号公式**断言（跟随 NotchStyle 常量，常量改了测试照样过）
/// - 本文件补**字面量锚点**（常量一旦被改立刻 fail）+ 现有文件没覆盖的边界组合
@MainActor
final class IslandGeometryEdgeTests: XCTestCase {

    // MARK: - 1. 超大刘海宽度：公式不溢出、不变号

    /// 防御性锚点：notchWidth 远超真实设备（5000pt）时公式仍逐项成立。
    /// 真实设备刘海 ~200pt 左右，但 compute 是纯函数，输入异常时不应产出负值 / NaN。
    func testCompute_withHugeNotchWidth_formulaStillHolds() {
        guard NotchStyle.autoDetect else { return }
        let huge: CGFloat = 5000
        let geo = IslandGeometry.compute(hasNotch: true, notchWidth: huge, menuBarHeight: 24)
        let sidePad = max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6

        XCTAssertEqual(geo.expanded.width,
                       huge + 2 * NotchStyle.expandedSideExtension,
                       accuracy: 0.01, "超大刘海展开态宽公式应仍成立")
        XCTAssertEqual(geo.collapsed.width,
                       sidePad + NotchStyle.levelIconSize
                       + (huge + NotchStyle.collapsedMiddleExtra)
                       + NotchStyle.progressRingSize + sidePad,
                       accuracy: 0.01, "超大刘海折叠态宽公式应仍成立")
        XCTAssertFalse(geo.collapsed.width.isNaN)
        XCTAssertFalse(geo.expanded.width.isNaN)
        XCTAssertGreaterThan(geo.collapsed.width, 0)
    }

    // MARK: - 2. collapsedH 护栏边界：max(menuBarHeight, 24) 的三段取值

    /// 现有测试只覆盖 menuBarHeight=0；补 12（护栏下）/ 24（恰等护栏）/ 38（护栏上）。
    func testCollapsedHeightGuardRail_boundaryValues() {
        guard NotchStyle.autoDetect else { return }

        let below = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 12)
        XCTAssertEqual(below.collapsed.height, 24, accuracy: 0.01,
                       "menuBarHeight=12 < 24 应被护栏抬到 24")

        let exact = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 24)
        XCTAssertEqual(exact.collapsed.height, 24, accuracy: 0.01,
                       "menuBarHeight=24 恰好等于护栏")

        let above = IslandGeometry.compute(hasNotch: true, notchWidth: 220, menuBarHeight: 38)
        XCTAssertEqual(above.collapsed.height, 38, accuracy: 0.01,
                       "menuBarHeight=38 > 24 应原样使用（护栏不压低）")
        // menuBarHeight 字段原样保留（展开态顶行高度按真实值布局，不走护栏）
        XCTAssertEqual(above.menuBarHeight, 38, accuracy: 0.01)
        XCTAssertEqual(below.menuBarHeight, 12, accuracy: 0.01)
    }

    // MARK: - 3. islandRect 的 isFlipped 两分支 × 展开/折叠 全组合 y 换算

    /// 现有测试只断言 (折叠, isFlipped=false) 一个组合的 y；这里 4 组合全覆盖 + x 居中。
    /// 生产调用链：PassthroughHostingView.hitTest 传自身 isFlipped（NSHostingView 默认 true），
    /// refreshHoverState 算全局坐标时传 false（窗口坐标系 y 向上）——两分支都是活代码。
    func testIslandRect_flippedBranches_fullMatrix() {
        let geo = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 24)
        let panel = NSSize(width: geo.expanded.width + 200, height: geo.expanded.height + 100)

        // (展开, flipped=true)：y=0 = panel 顶
        var r = geo.islandRect(isExpanded: true, in: panel, isFlipped: true)
        XCTAssertEqual(r.minY, 0, accuracy: 0.01, "flipped 展开态 y 应为 0（顶对齐）")
        XCTAssertEqual(r.width, geo.expanded.width, accuracy: 0.01)
        XCTAssertEqual(r.height, geo.expanded.height, accuracy: 0.01)
        XCTAssertEqual(r.minX, (panel.width - geo.expanded.width) / 2, accuracy: 0.01)

        // (展开, flipped=false)：y = panelH - expandedH（y 向上坐标系里贴顶）
        r = geo.islandRect(isExpanded: true, in: panel, isFlipped: false)
        XCTAssertEqual(r.minY, panel.height - geo.expanded.height, accuracy: 0.01,
                       "unflipped 展开态 y 应为 panelH - islandH")
        XCTAssertEqual(r.width, geo.expanded.width, accuracy: 0.01)
        XCTAssertEqual(r.height, geo.expanded.height, accuracy: 0.01)

        // (折叠, flipped=true)：y=0
        r = geo.islandRect(isExpanded: false, in: panel, isFlipped: true)
        XCTAssertEqual(r.minY, 0, accuracy: 0.01, "flipped 折叠态 y 应为 0")
        XCTAssertEqual(r.width, geo.collapsed.width, accuracy: 0.01)
        XCTAssertEqual(r.height, geo.collapsed.height, accuracy: 0.01)
        XCTAssertEqual(r.minX, (panel.width - geo.collapsed.width) / 2, accuracy: 0.01)

        // (折叠, flipped=false)：y = panelH - collapsedH
        r = geo.islandRect(isExpanded: false, in: panel, isFlipped: false)
        XCTAssertEqual(r.minY, panel.height - geo.collapsed.height, accuracy: 0.01,
                       "unflipped 折叠态 y 应为 panelH - collapsedH")
        XCTAssertEqual(r.width, geo.collapsed.width, accuracy: 0.01)
        XCTAssertEqual(r.height, geo.collapsed.height, accuracy: 0.01)
    }

    // MARK: - 4. panel 比岛窄：x 算出负值不 clamp（文档化现状行为）

    /// createWindow 恒用 expanded.width+40 做 panel 宽，正常不会触发；
    /// 但纯函数本身不做 clamp——若未来有调用方传更小的 panelSize，
    /// 负 x 会让岛向左溢出而非静默 clamp。本用例把现状钉住，改动时必须显式确认。
    func testIslandRect_panelNarrowerThanIsland_negativeXNotClamped() {
        let geo = IslandGeometry.compute(hasNotch: true, notchWidth: 220, menuBarHeight: 24)
        let narrow = NSSize(width: geo.collapsed.width - 40, height: 300)

        let r = geo.islandRect(isExpanded: false, in: narrow, isFlipped: true)

        XCTAssertEqual(r.minX, (narrow.width - geo.collapsed.width) / 2, accuracy: 0.01,
                       "x 公式应为 (panelW - islandW)/2，不做 clamp")
        XCTAssertLessThan(r.minX, 0, "panel 比岛窄时 x 应为负（现状行为，钉住防静默变更）")
    }

    // MARK: - 5. NotchStyle 常量字面量锚点（常量漂移警报器）

    /// 现有符号公式测试在常量被改时照样通过（公式两边同步变化）；
    /// 字面量锚点则会在任何常量调整时立刻 fail——这是特性：
    /// fail 信息即"几何变了"，确认是有意调整视觉后更新锚点即可。
    /// 锚点推导（当前常量：topR=8 / bottomR=14 → sidePad=max(8,14)+6=20；
    /// icon=16 / ring=18 / middleExtra=8 / ext=110 / compactGap=8 / expandedH=150 /
    /// minExpandedWidthNoNotch=440）：
    /// - 有刘海折叠宽 = 20+16+(220+8)+18+20 = 302
    /// - 有刘海展开宽 = 220+2×110 = 440
    /// - 无刘海折叠宽 = 20+16+(220+8)+18+20 = 302（虚拟刘海 220，与有刘海同宽）
    /// - 无刘海展开宽 = max(2×110+8, 440) = 440（228 低于下限，被 minExpandedWidthNoNotch 抬起）
    func testNotchStyleConstantAnchors() {
        guard NotchStyle.autoDetect else { return }

        let notchGeo = IslandGeometry.compute(hasNotch: true, notchWidth: 220, menuBarHeight: 24)
        XCTAssertEqual(notchGeo.collapsed.width, 302, accuracy: 0.01,
                       "锚点 fail = NotchStyle 常量被改动：有刘海折叠宽 302 = 20+16+228+18+20")
        XCTAssertEqual(notchGeo.expanded.width, 440, accuracy: 0.01,
                       "锚点 fail = 常量改动：有刘海展开宽 440 = 220+2×110")
        XCTAssertEqual(notchGeo.collapsed.height, 24, accuracy: 0.01)

        let compactGeo = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 24)
        XCTAssertEqual(compactGeo.collapsed.width, 302, accuracy: 0.01,
                       "锚点 fail = 常量改动：无刘海折叠宽 302 = 20+16+(220+8)+18+20（虚拟刘海）")
        XCTAssertEqual(compactGeo.expanded.width, 440, accuracy: 0.01,
                       "锚点 fail = 常量改动：无刘海展开宽 440 = max(2×110+8, 440)，下限生效")
        XCTAssertEqual(compactGeo.expanded.height, 150, accuracy: 0.01,
                       "锚点 fail = expandedHeight 常量改动（当前 150）")
    }

    // MARK: - 6. 无刘海展开态最小宽度下限（minExpandedWidthNoNotch）语义

    /// Bug 锚点：无刘海外接显示器展开态曾只有 228pt（2×110+8），promise/reasoning 被截断。
    /// 修复语义：无刘海展开宽 = max(2×ext + compactGap, minExpandedWidthNoNotch)，
    /// 即"公式结果"与"下限"取大者；当前常量下 228 < 440，下限必须生效。
    func testNoNotchExpandedWidth_floorSemantics() {
        guard NotchStyle.autoDetect else { return }

        let geo = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 24)
        let formula = 2 * NotchStyle.expandedSideExtension + NotchStyle.collapsedCompactGap

        XCTAssertEqual(geo.expanded.width,
                       max(formula, NotchStyle.minExpandedWidthNoNotch),
                       accuracy: 0.01,
                       "无刘海展开宽应为 max(2×ext + compactGap, minExpandedWidthNoNotch)")
        XCTAssertGreaterThanOrEqual(geo.expanded.width, NotchStyle.minExpandedWidthNoNotch,
                                    "无刘海展开宽不得低于 minExpandedWidthNoNotch（440）")
        XCTAssertGreaterThanOrEqual(geo.expanded.width, 440,
                                    "回归锚点：无刘海展开宽至少 440（与有刘海典型展开宽对齐）")
        // 当前常量下公式结果（228）确实低于下限——下限分支是活代码，不是死兜底
        XCTAssertLessThan(formula, NotchStyle.minExpandedWidthNoNotch,
                          "当前常量应触发下限分支；若常量调整使公式超过下限，本断言需同步复核")
    }

    // MARK: - 7. 展开态顶行中段宽（expandedTopRowMiddleWidth）：两端 flank 锚点

    /// Bug 锚点（440 下限的第二部分）：无刘海屏展开宽抬到 440 后，
    /// 顶行三段式（左 capsule 110 / 中段 / 右 timer 110）的中段若仍是 compactGap(8)，
    /// 顶行总宽只有 228，在 440 宽岛里居中悬浮（两侧各 ~106pt 空白），
    /// 与有刘海屏"capsule 贴左外、timer 贴右外"的 flank 语言不一致。
    /// 修复语义：中段宽 = expanded.width - 2×expandedSideExtension，顶行铺满岛宽。

    /// 有刘海屏：中段恒等于物理刘海宽——与改版前逐像素一致（硬约束，不许动）
    func testExpandedTopRowMiddleWidth_hasNotch_equalsNotchWidth() {
        guard NotchStyle.autoDetect else { return }
        let geo = IslandGeometry.compute(hasNotch: true, notchWidth: 220, menuBarHeight: 24)

        XCTAssertEqual(geo.expandedTopRowMiddleWidth, geo.notchWidth, accuracy: 0.01,
                       "有刘海顶行中段宽必须恒等于 notchWidth（物理刘海占位，逐像素不变）")
        XCTAssertEqual(geo.expandedTopRowMiddleWidth, 220, accuracy: 0.01,
                       "字面量锚点：有刘海中段宽 220")
        // 顶行三段合计 = 展开总宽（flank 布局的既有不变量）
        XCTAssertEqual(2 * NotchStyle.expandedSideExtension + geo.expandedTopRowMiddleWidth,
                       geo.expanded.width, accuracy: 0.01,
                       "有刘海顶行三段合计应等于展开总宽")
    }

    /// 无刘海屏：中段 = 展开总宽 - 两侧凹陷区，三段合计铺满 440，不再居中悬浮
    func testExpandedTopRowMiddleWidth_noNotch_fillsIslandWidth() {
        guard NotchStyle.autoDetect else { return }
        let geo = IslandGeometry.compute(hasNotch: false, notchWidth: 220, menuBarHeight: 24)

        XCTAssertEqual(geo.expandedTopRowMiddleWidth,
                       geo.expanded.width - 2 * NotchStyle.expandedSideExtension,
                       accuracy: 0.01,
                       "无刘海顶行中段宽应为 expanded.width - 2×expandedSideExtension")
        XCTAssertGreaterThanOrEqual(geo.expandedTopRowMiddleWidth,
                                    NotchStyle.collapsedCompactGap,
                                    "无刘海中段宽不得低于紧凑间距下限")
        // 修复核心断言：三段合计 = 展开总宽 → capsule/timer 两端 flank
        XCTAssertEqual(2 * NotchStyle.expandedSideExtension + geo.expandedTopRowMiddleWidth,
                       geo.expanded.width, accuracy: 0.01,
                       "无刘海顶行三段合计应铺满展开总宽（440），不再 228 居中悬浮")
        // 字面量锚点：440 - 2×110 = 220
        XCTAssertEqual(geo.expandedTopRowMiddleWidth, 220, accuracy: 0.01,
                       "字面量锚点：无刘海中段宽 220 = 440 - 2×110")
    }

    /// 极端窄岛（展开宽 < 2×ext，直接构造的防御性输入）：中段回退 compactGap，不出负宽
    func testExpandedTopRowMiddleWidth_extremeNarrowIsland_floorsAtCompactGap() {
        let narrow = IslandGeometry(
            collapsed: CGSize(width: 82, height: 24),
            expanded: CGSize(width: 100, height: NotchStyle.expandedHeight),
            hasNotch: false, notchWidth: 0, menuBarHeight: 24
        )
        XCTAssertEqual(narrow.expandedTopRowMiddleWidth, NotchStyle.collapsedCompactGap,
                       accuracy: 0.01,
                       "展开宽 < 2×ext 时中段应回退 compactGap（max 下限防负宽）")
        XCTAssertGreaterThan(narrow.expandedTopRowMiddleWidth, 0)
    }
}
