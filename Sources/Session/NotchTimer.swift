import AppKit
import SwiftUI

// MARK: - ✏️ 可调参数

/// 改下面这些常量，光标点进文件底部 `#Preview` 任一段，按 ⌥⌘↩ 打开 Canvas 实时预览。
///
/// 默认 autoDetect=true 时，折叠态宽高自动跟随物理刘海尺寸；
/// 关掉 autoDetect 用下面的手动值。
enum NotchStyle {
    /// 自动检测物理刘海宽度 + 菜单栏高度（推荐）
    static let autoDetect: Bool = true

    /// autoDetect 时，折叠态宽度由内容驱动：
    /// 总宽 = leftItem(圆点) + (notchWidth + middleExtra) + rightItem(圆环) + 2 × sidePad
    /// 这个值是"中间预留空白"在物理刘海宽度基础上的额外量。
    /// 调小 = 岛更紧凑（可能与刘海重叠 → 不影响可见性，因为内容在两端）；
    /// 调大 = 中间空白更宽。
    static let collapsedMiddleExtra: CGFloat = 8

    /// autoDetect 时，展开态在物理刘海宽度基础上左右各扩展多少 pt。
    /// 例如：刘海 220 + extension 110 → 岛总宽 440。
    static let expandedSideExtension: CGFloat = 110

    /// 无刘海屏的紧凑间距：折叠态图标与圆环之间、展开态左右凹陷区之间的固定间距。
    /// 有刘海屏不用它——那里的"间距"是物理刘海宽度（+ collapsedMiddleExtra）。
    static let collapsedCompactGap: CGFloat = 8

    /// 无刘海屏展开态宽度下限。
    /// 无刘海公式 2×expandedSideExtension + compactGap 只有 228pt，
    /// 展开态失去"刘海占位"这个宽度锚点，promise / reasoning 文字会被截断。
    /// 与有刘海典型展开宽（刘海 220 + 两侧扩展 2×110 = 440）对齐：
    /// 公式结果低于此值时抬到 440，给菜单栏下方内容区足够横向空间。
    static let minExpandedWidthNoNotch: CGFloat = 440

    /// 折叠态圆环直径
    /// 视觉平衡：圆环 18 + level 图标 16，两侧观感等重；
    /// 旧值 22 + 14 偏向右重，环像耳坠左像针眼。
    static let progressRingSize: CGFloat = 18
    /// 折叠态圆环描边宽度（Apple Watch 运动圆环感觉，越大越"实"）
    /// 圆环直径缩到 18 后，4pt 描边占比过大显得笨拙，降到 3pt。
    static let progressRingLineWidth: CGFloat = 3
    /// 折叠态左端 level 状态图标大小
    static let levelIconSize: CGFloat = 16

    /// 展开态左侧（刘海左方）倒计时字号——比旧版 28pt 大头小，
    /// 因为新布局把 timer 嵌进菜单栏高度的凹陷区，必须收敛到 ~20pt。
    static let expandedTimerFontSize: CGFloat = 20

    // ===== 手动尺寸（autoDetect=false 时生效）=====
    static let manualCollapsedWidth: CGFloat = 380
    static let manualCollapsedHeight: CGFloat = 32
    static let manualExpandedWidth: CGFloat = 440

    // ===== 展开态高度（无论 autoDetect 都用这个）=====
    /// 注意：展开态内容会自动加 `menuBarHeight` 顶部 padding 让内容在菜单栏下方显示。
    /// 所以实际可用内容高 = expandedHeight - menuBarHeight - 14（底部 padding）。
    /// 例如 150 - 38 - 14 = 98pt 给倒计时 + promise + reminder。
    static let expandedHeight: CGFloat = 150

    // ===== 形状圆角 =====
    /// 顶部 concave 圆角（反向，圆心在外）
    static let topCornerRadius: CGFloat = 8
    /// 底部 convex 圆角（正向，圆心在内）
    static let bottomCornerRadius: CGFloat = 14

    // ===== 内容布局 =====
    /// 折叠态内容贴向哪一侧（避开物理刘海摄像头中央区域）
    static let collapsedContentAlignment: ContentAlignment = .split

    // ===== distracted 描边 =====
    static let distractedBorderWidth: CGFloat = 2.0
    static let distractedBorderColor: Color = .red

    // ===== 动画 =====
    static let springResponse: Double = 0.42
    static let springDamping: Double = 0.78
    /// distracted 跳变时刘海强制展开的秒数（原 6s 太短看不清 reminder，加长到 18s）
    static let distractedFlashSeconds: TimeInterval = 18

    enum ContentAlignment {
        case leading, trailing, center, split
    }
}

// MARK: - 岛尺寸 Single Source

/// 刘海岛的折叠 / 展开几何尺寸。
///
/// 由 `IslandGeometry.compute(...)` 统一计算，调用方（各屏 controller 的
/// currentIslandRect / NotchView / createWindow、NotchTimer 兼容壳）都从这里读，
/// 不再各自重复 autoDetect 分支逻辑。
struct IslandGeometry {
    /// 折叠态尺寸（宽 = 内容驱动；高 = 菜单栏高度）
    let collapsed: CGSize
    /// 展开态尺寸（宽 = notchWidth + 两侧扩展；高 = NotchStyle.expandedHeight）
    let expanded: CGSize
    /// 该屏是否有物理刘海——无刘海屏折叠态不留假刘海空白
    let hasNotch: Bool
    /// 物理刘海宽度（pt）。仅 hasNotch=true 时参与布局
    let notchWidth: CGFloat
    /// 菜单栏高度（含刘海机型的刘海高度）
    let menuBarHeight: CGFloat

    /// 新字段全部带默认值——旧的 `IslandGeometry(collapsed:expanded:)` 构造点不破坏（additive）
    init(collapsed: CGSize, expanded: CGSize,
         hasNotch: Bool = true, notchWidth: CGFloat = 220, menuBarHeight: CGFloat = 24) {
        self.collapsed = collapsed
        self.expanded = expanded
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.menuBarHeight = menuBarHeight
    }
}

extension IslandGeometry {
    /// 纯函数工厂——不读 NSScreen，CI 可测。
    ///
    /// 有刘海分支公式与改版前 `NotchTimer.islandGeometry` 逐项相等（硬要求，
    /// NotchGeometryTests 原样通过即证据）；无刘海分支是新增的紧凑几何：
    /// - 折叠态宽 = sidePad + icon + compactGap + ring + sidePad（不留假刘海区）
    /// - 展开态宽 = max(2×expandedSideExtension + compactGap, minExpandedWidthNoNotch)
    ///   ——紧凑公式只有 228pt 会截断 promise/reasoning，用下限 440 锚住展开宽度
    static func compute(hasNotch: Bool, notchWidth: CGFloat, menuBarHeight: CGFloat) -> IslandGeometry {
        let collapsedW: CGFloat
        let collapsedH: CGFloat
        let expandedW: CGFloat

        if NotchStyle.autoDetect {
            // 折叠态：两侧 padding + 左端 level 图标 + 中段 + 右端进度圆环
            let sidePad = max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6
            if hasNotch {
                // 中段 = 物理刘海宽 + 额外留白（与旧实现逐项相等）
                collapsedW = sidePad + NotchStyle.levelIconSize
                           + (notchWidth + NotchStyle.collapsedMiddleExtra)
                           + NotchStyle.progressRingSize + sidePad
                // 展开态：物理刘海宽 + 两侧各扩展 expandedSideExtension（与旧实现逐项相等）
                expandedW = notchWidth + 2 * NotchStyle.expandedSideExtension
            } else {
                // 无刘海屏：中段仅留紧凑固定间距
                collapsedW = sidePad + NotchStyle.levelIconSize
                           + NotchStyle.collapsedCompactGap
                           + NotchStyle.progressRingSize + sidePad
                // 展开态：紧凑公式（228）失去刘海占位这个宽度锚点，
                // 用 minExpandedWidthNoNotch（440，对齐有刘海典型宽）兜底，避免内容截断
                expandedW = max(2 * NotchStyle.expandedSideExtension + NotchStyle.collapsedCompactGap,
                                NotchStyle.minExpandedWidthNoNotch)
            }
            // 折叠态高度跟随菜单栏；无菜单栏的副屏（罕见配置）回退 24 避免 0 高岛。
            // 有刘海 / 主屏 / 无头回退路径 menuBarHeight 恒 ≥ 24，max 不改变既有结果。
            collapsedH = max(menuBarHeight, 24)
        } else {
            collapsedW = NotchStyle.manualCollapsedWidth
            collapsedH = NotchStyle.manualCollapsedHeight
            expandedW  = NotchStyle.manualExpandedWidth
        }

        return IslandGeometry(
            collapsed: CGSize(width: collapsedW, height: collapsedH),
            expanded:  CGSize(width: expandedW,  height: NotchStyle.expandedHeight),
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            menuBarHeight: menuBarHeight
        )
    }

    /// 便捷壳：按屏幕实测参数计算。
    /// nil（CI 无头环境）按旧行为"有刘海 + 回退值"处理——旧 islandGeometry 不判 hasNotch
    /// 恒走刘海公式，保证 `NotchTimer.islandGeometry` 兼容壳与现状逐字节一致。
    @MainActor
    static func compute(for screen: NSScreen?) -> IslandGeometry {
        if let screen {
            return compute(
                hasNotch: ScreenMetrics.hasNotchedDisplay(for: screen),
                notchWidth: ScreenMetrics.notchWidth(for: screen),
                menuBarHeight: ScreenMetrics.menuBarHeight(for: screen)
            )
        }
        return compute(
            hasNotch: true,
            notchWidth: ScreenMetrics.notchWidth(for: nil),
            menuBarHeight: ScreenMetrics.menuBarHeight(for: nil)
        )
    }

    /// 当前岛实际矩形（panel-local 坐标）——矩形数学纯函数，
    /// NotchIslandController 与 NotchTimer 兼容壳共用，保证旧测试断言路径仍然有效。
    /// - isExpanded: 由调用方按自身 hovering + 全局 forceExpandUntil 算出
    /// - isFlipped: NSHostingView.isFlipped — true 时 y=0 是顶，false 时 y=0 是底
    func islandRect(isExpanded: Bool, in panelSize: NSSize, isFlipped: Bool) -> NSRect {
        // 不再下移：菜单栏区有了 timer/status 内容后，3pt 偏移变成可见空隙，
        // 接受顶部 concave 角点 1pt stroke 被屏幕顶截掉的代价（曲线本体在 y≥0 内不受影响）
        let topInset: CGFloat = 0
        let islandSize = isExpanded ? expanded : collapsed

        let x = (panelSize.width - islandSize.width) / 2
        // SwiftUI VStack 顶端对齐 panel 顶；岛在 panel 顶往下 topInset 起
        // isFlipped=true（NSHostingView 默认）：y=0=顶 → islandY = topInset
        // isFlipped=false（普通 NSView）：y=panelH=顶 → islandY = panelH - topInset - islandH
        let y: CGFloat
        if isFlipped {
            y = topInset
        } else {
            y = panelSize.height - topInset - islandSize.height
        }
        return NSRect(x: x, y: y, width: islandSize.width, height: islandSize.height)
    }
}

// MARK: - 状态

/// 软提醒级别——distract 之外的两种轻量提示。
/// 决定刘海描边色 + 文案样式；distract 仍由 state.level == .distracted 判断（最高优先级）。
enum SoftReminderLevel {
    case none
    case wandering   // 持续走神，黄色描边 + 12s 展开
    case idle        // 长时间不在电脑前，橙色描边 + 持续展开 + 周期声音
}

/// 单条分析点——TimelineBar 把它按 bin 时间分箱，每箱取众数 level 上色。
/// 用 struct 而非直接拿 AnalysisRecord，避免 SwiftData @Model 跨线程隐患。
struct TimelineEntry: Equatable {
    let timestamp: Date
    let level: FocusLevel
}

@MainActor
final class NotchTimer: ObservableObject {
    static let shared = NotchTimer()

    @Published var remaining: TimeInterval = 0
    @Published var planned: TimeInterval = 0   // 总时长，用于算圆环进度
    @Published var level: FocusLevel? = nil
    @Published var promise: String = ""
    @Published var reasoning: String = ""     // AI 每帧的活动描述
    @Published var reminder: String = ""      // 仅 distracted 时的拉回提醒
    @Published var forceExpandUntil: Date? = nil

    /// idle / wandering 软提醒文案（distract 走 reminder 字段）
    @Published var softReminderMessage: String = ""
    @Published var softReminderLevel: SoftReminderLevel = .none

    /// 本次会话起始时间——TimelineBar 算 bin 边界用绝对时间。
    /// show() 时设，hide() 时清。
    @Published var sessionStart: Date? = nil

    /// 已经发生的分析点序列，按时间升序追加。
    /// 长度上限：planned/captureInterval（约 720 for 60min @5s）；不裁剪即可。
    @Published var timeline: [TimelineEntry] = []

    /// 每屏一座岛，key = CGDirectDisplayID。
    /// 由 syncControllers() 按 NSScreen.screens diff 维护；hide() 全量 teardown 后清空。
    private(set) var controllers: [CGDirectDisplayID: NotchIslandController] = [:]

    /// 屏幕参数变化（热插拔 / 分辨率 / 排列）通知的观察 token——随 singleton 生命周期，无需手动移除
    private var screenParamsObserver: NSObjectProtocol?
    /// 热插拔 0.3s 合并防抖任务——新通知到来时取消上一个，只重建最后一次
    private var screenChangeDebounceTask: Task<Void, Never>?

    private init() {
        // 屏幕热插拔 / 分辨率变化监听。该通知一次插拔会连发多条（含分辨率中间态），
        // 统一走 0.3s 合并防抖后再重建，避免短时间反复 teardown/show。
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenParametersChanged()
            }
        }
    }

    /// hovering 已下沉到各屏 NotchIslandController（hover 只展开被 hover 的那座岛）。
    /// 这里是主屏 controller 的代理兼容壳——测试与旧调用方零改动；
    /// 无 controller（测试环境未 show()）时恒 false、写入静默丢弃。
    var hovering: Bool {
        get { mainController?.hovering ?? false }
        set { mainController?.hovering = newValue }
    }

    /// 主屏对应的 controller；取不到时退任意一座（保证代理有确定性去向）
    private var mainController: NotchIslandController? {
        if let mainID = NSScreen.main?.displayID, let c = controllers[mainID] {
            return c
        }
        return controllers.values.first
    }

    /// 按当前屏幕集合 diff controllers——show() 与后续热插拔阶段共用。
    /// 新屏建 controller、拔掉的屏 teardown 后移除（teardown 配对释放，防泄漏）。
    func syncControllers() {
        var alive: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            alive.insert(id)
            if controllers[id] == nil {
                controllers[id] = NotchIslandController(screen: screen, state: self)
            }
        }
        let stale = controllers.keys.filter { !alive.contains($0) }
        for id in stale {
            controllers[id]?.teardown()
            controllers.removeValue(forKey: id)
        }
    }

    func show(promise: String, plannedSeconds: Int) {
        self.promise = promise
        self.planned = TimeInterval(plannedSeconds)
        // 重置 timeline——上一次会话残留数据不能复用到本次
        self.sessionStart = Date()
        self.timeline.removeAll()
        syncControllers()
        for controller in controllers.values {
            controller.show()
        }
    }

    func hide() {
        for controller in controllers.values {
            controller.teardown()
        }
        controllers.removeAll()
        forceExpandUntil = nil
        sessionStart = nil
        timeline.removeAll()
    }

    // MARK: - 屏幕热插拔

    /// 屏幕参数变化通知入口——0.3s 合并防抖：一次插拔 / 改分辨率会连发多条通知，
    /// 只重建最后一次（任务可取消，重建前 cancel 上一个）。
    private func handleScreenParametersChanged() {
        screenChangeDebounceTask?.cancel()
        screenChangeDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.rebuildControllersForScreenChange()
        }
    }

    /// 热插拔 / 分辨率 / 排列变化后全重建全部岛。
    /// 全重建而非 diff：分辨率 / 排列变化时，存活屏的旧 panel frame 也已失效，diff 无意义。
    /// 业务状态（remaining / level / timeline / forceExpandUntil）都在 NotchTimer 本体，
    /// 重建只换各屏 panel 与几何——重建后 UI 立即恢复，剩余时间 / 级别 / 时间线不丢。
    /// 连续触发 N 次结果一致（幂等）；镜像屏（NSScreen.screens 含镜像对）会在同一
    /// 物理输出上重叠显示相同内容，无害不处理。
    private func rebuildControllersForScreenChange() {
        // 未在显示（controllers 为空）时通知空转，零成本
        guard !controllers.isEmpty else { return }
        for controller in controllers.values {
            controller.teardown()   // 配对释放：关窗 + 摘两个 monitor + invalidate Timer
        }
        controllers.removeAll()
        syncControllers()
        for controller in controllers.values {
            controller.show()
        }
    }

    /// SessionManager 每写一条 AnalysisRecord 就调一次，按 createdAt 追加。
    /// 顺序由调用方保证（5s tick 串行）；这里不做去重 / 排序。
    func appendAnalysis(at timestamp: Date, level: FocusLevel) {
        timeline.append(TimelineEntry(timestamp: timestamp, level: level))
    }

    func update(remaining: TimeInterval, level: FocusLevel?) {
        self.remaining = remaining
        self.level = level
    }

    /// 每次 AI 返回更新一下，让展开态能看到当前 AI 怎么描述屏幕活动
    func updateAIFeedback(reasoning: String) {
        self.reasoning = reasoning
    }

    func flashDistracted(reminder: String) {
        self.reminder = reminder
        self.forceExpandUntil = Date().addingTimeInterval(NotchStyle.distractedFlashSeconds)
    }

    /// 持续走神软提示：12s 展开 + 黄色描边
    func flashWandering(message: String, seconds: TimeInterval = 12) {
        self.softReminderMessage = message
        self.softReminderLevel = .wandering
        self.forceExpandUntil = Date().addingTimeInterval(seconds)
    }

    /// 长时间 idle 软提示：持续展开 + 橙色描边，直到 stopSoftReminder() 调用
    func flashIdle(message: String) {
        self.softReminderMessage = message
        self.softReminderLevel = .idle
        self.forceExpandUntil = .distantFuture
    }

    /// 当前岛实际矩形——主屏兼容壳，矩形数学复用共享纯函数
    /// （实际生产路径在各屏 NotchIslandController.currentIslandRect）。
    /// - panelSize: NSHostingView.bounds.size
    /// - isFlipped: NSHostingView.isFlipped — true 时 y=0 是顶，false 时 y=0 是底
    func currentIslandRect(in panelSize: NSSize, isFlipped: Bool = true) -> NSRect {
        let isExpanded = hovering || (forceExpandUntil.map { $0 > Date() } ?? false)
        return islandGeometry.islandRect(isExpanded: isExpanded, in: panelSize, isFlipped: isFlipped)
    }

    /// 停止 idle / wandering 软提醒（用户回来动一下 / hover 岛 / level 切换）
    func stopSoftReminder() {
        softReminderLevel = .none
        softReminderMessage = ""
        if let until = forceExpandUntil, until == .distantFuture {
            // 仅清掉 idle 那种"无限期"展开；wandering 让自然超时
            forceExpandUntil = nil
        }
    }

    // MARK: - 岛尺寸 Single Source

    /// 折叠 / 展开几何尺寸的主屏兼容壳——公式已集中到 IslandGeometry.compute，
    /// 各屏 controller 用 `IslandGeometry.compute(for: 自己的屏)`。
    /// 保留此壳让 NotchGeometryTests 等旧调用方零改动（有刘海主屏 / 无头环境下
    /// 与改版前逐项相等）。
    var islandGeometry: IslandGeometry {
        IslandGeometry.compute(for: .main)
    }
}

// MARK: - View

struct NotchView: View {
    @ObservedObject var state: NotchTimer
    @ObservedObject var controller: NotchIslandController
    @State private var now = Date()
    private var hovering: Bool { controller.hovering }

    /// 从所在屏的 controller 读岛尺寸（每屏几何可能不同：有 / 无刘海），
    /// 避免与 currentIslandRect / createWindow 各自重复计算。
    private var geo: IslandGeometry { controller.islandGeometry }

    /// 折叠态宽度
    private var collapsedWidth: CGFloat { geo.collapsed.width }

    /// 展开态宽度
    private var expandedWidth: CGFloat { geo.expanded.width }

    /// 折叠态高度
    private var collapsedHeight: CGFloat { geo.collapsed.height }

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(
                    width: isExpanded ? expandedWidth : collapsedWidth,
                    height: isExpanded ? NotchStyle.expandedHeight : collapsedHeight
                )
                // 不再下移补偿——菜单栏区放了内容后，3pt 偏移变成可见空隙比 stroke
                // 角点 1pt 截切更难看。接受角点 1pt 视觉牺牲，岛永远贴顶
                .padding(.top, 0)
                .animation(
                    .spring(response: NotchStyle.springResponse, dampingFraction: NotchStyle.springDamping),
                    value: isExpanded
                )
            Spacer(minLength: 0)
        }
        .frame(width: expandedWidth + 40, height: NotchStyle.expandedHeight + 8)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
        }
    }

    private var isExpanded: Bool {
        if hovering { return true }
        if let until = state.forceExpandUntil, until > now { return true }
        return false
    }

    private var isDistracted: Bool { state.level == .distracted }
    private var isStrongAlert: Bool { isDistracted }
    private var isSoftAlert: Bool {
        state.softReminderLevel == .idle || state.softReminderLevel == .wandering
    }

    /// 描边色优先级：distract > idle > wandering > 默认浅灰
    private var borderColor: Color {
        if isDistracted { return NotchStyle.distractedBorderColor }
        switch state.softReminderLevel {
        case .idle: return .orange
        case .wandering: return .yellow
        case .none: return Color.white.opacity(0.08)
        }
    }
    private var borderWidth: CGFloat {
        if isDistracted { return NotchStyle.distractedBorderWidth }
        return isSoftAlert ? 1.5 : 0.5
    }

    /// 岛本体 — 反向圆角形状 + 描边 + 内容，共享同一 shape 保证缩放同步
    private var island: some View {
        ZStack {
            shape.fill(.black)
            content
        }
        .clipShape(shape)
        // 描边放在 clipShape 之后：center-aligned stroke 在 concave 顶角处
        // 朝外那半像素本来会被 clipShape 裁掉（看起来上圆角"没了"），
        // 放到外层 overlay 后整条 U 形线包括两个反向圆角都能完整显示
        .overlay(
            NotchBottomBorder(
                topCornerRadius: NotchStyle.topCornerRadius,
                bottomCornerRadius: NotchStyle.bottomCornerRadius
            )
            .stroke(borderColor, lineWidth: borderWidth)
        )
        .onHover { isHovering in
            controller.hovering = isHovering
            // 用户 hover 到岛 = 已经"看到提醒"，立刻清掉强制展开 + 停 idle/wandering 软提醒
            // （forceExpandUntil 是全局状态：hover 任意一座岛，全部岛一起收起）
            if isHovering {
                if state.forceExpandUntil != nil {
                    state.forceExpandUntil = nil
                }
                if state.softReminderLevel != .none {
                    state.stopSoftReminder()
                }
            }
        }
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.title == "Vigil" {
                w.makeKeyAndOrderFront(nil)
            }
        }
    }

    private var shape: NotchShape {
        NotchShape(
            topCornerRadius: NotchStyle.topCornerRadius,
            bottomCornerRadius: NotchStyle.bottomCornerRadius
        )
    }

    @ViewBuilder
    private var content: some View {
        if isExpanded {
            expandedContent.transition(.opacity)
        } else {
            collapsedContent.transition(.opacity)
        }
    }

    // MARK: 折叠态内容（左端 level 图标 + 右端进度圆环）

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            // 左端：level 状态图标（露出在物理刘海左侧）
            Image(systemName: levelIconName)
                .font(.system(size: NotchStyle.levelIconSize, weight: .semibold))
                .foregroundStyle(levelColor)
                .frame(width: NotchStyle.levelIconSize + 2)
                .animation(.easeInOut(duration: 0.18), value: state.level)
            if geo.hasNotch {
                Spacer(minLength: 0)
            } else {
                // 无刘海屏：不留跨刘海的大段空白，间距收窄到紧凑上限
                // （maxWidth 而非固定宽——弹性吸收像素取整，保证内容永不溢出岛体）
                Spacer(minLength: 0).frame(maxWidth: NotchStyle.collapsedCompactGap)
            }
            // 右端：进度圆环（露出在物理刘海右侧）
            ProgressRing(
                progress: ringProgress,
                color: levelColor,
                size: NotchStyle.progressRingSize,
                lineWidth: NotchStyle.progressRingLineWidth
            )
        }
        .padding(.horizontal, max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6)
    }

    /// 折叠态左端的 level 状态图标名（SF Symbol）
    private var levelIconName: String {
        switch state.level {
        case .fully: return "leaf.fill"
        case .wandering: return "questionmark.circle.fill"
        case .distracted: return "exclamationmark.triangle.fill"
        case .idle: return "moon.stars.fill"
        case nil: return "circle.dashed"
        }
    }

    /// 圆环填充比例：剩余时间 / 总时长
    private var ringProgress: Double {
        guard state.planned > 0 else { return 0 }
        return max(0, min(1, state.remaining / state.planned))
    }

    // MARK: 展开态内容

    /// 新布局：顶行（menu bar 高度）= 刘海左侧 timer + 物理刘海空区 + 刘海右侧状态 capsule。
    /// 不再用 contentTopInset 把所有内容下推——菜单栏区由 topNotchRow 占用。
    /// 下方剩余空间放 timeline bar + promise + reasoning + reminder。
    private var expandedContent: some View {
        VStack(spacing: 0) {
            topNotchRow
                .frame(height: geo.menuBarHeight)
            bottomContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 顶行三段式（mirror 折叠态：左 level 图标 / 右进度圆环 → 左状态 capsule / 右 timer）
    /// 有刘海屏三段宽度合计 = expandedSideExtension + notchWidth + expandedSideExtension = 展开总宽；
    /// 无刘海屏中段换成 compactGap 固定间距。
    /// 内容贴外侧（远离刘海），让左右各自伸到岛尖头部分，视觉对称
    private var topNotchRow: some View {
        HStack(spacing: 0) {
            // 左侧凹陷区——状态 capsule，靠左对齐（外侧）
            HStack(spacing: 0) {
                Text(levelLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(levelColor.opacity(0.18), in: .capsule)
                Spacer(minLength: 0)
            }
            .padding(.leading, 24)
            .frame(width: NotchStyle.expandedSideExtension)

            // 中间——有刘海屏：物理刘海占位，不画内容；无刘海屏：固定紧凑间距
            Color.clear.frame(width: geo.hasNotch ? geo.notchWidth : NotchStyle.collapsedCompactGap)

            // 右侧凹陷区——倒计时，靠右对齐（外侧）
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(formatTime(state.remaining))
                    .font(.system(size: NotchStyle.expandedTimerFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.trailing, 24)
            .frame(width: NotchStyle.expandedSideExtension)
        }
    }

    /// 菜单栏下方的主内容区——timeline + promise + reasoning + reminder
    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 时间线条——session 全长，已发生的格按 level 上色，未来的格细灰
            FocusTimelineBar(
                timeline: state.timeline,
                sessionStart: state.sessionStart,
                plannedDuration: state.planned,
                now: now
            )
            .frame(height: 18)
            .padding(.top, 4)

            if !state.promise.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(state.promise)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            if !state.reasoning.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "eye")
                        .font(.caption2)
                        .foregroundStyle(levelColor)
                        .padding(.top, 2)
                    Text(state.reasoning)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                }
                .padding(.top, 2)
            }

            if isDistracted, !state.reminder.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                    Text(state.reminder)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.top, 2)
            }

            if !isDistracted, isSoftAlert, !state.softReminderMessage.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: state.softReminderLevel == .idle
                          ? "moon.zzz.fill"
                          : "wind")
                        .font(.caption2)
                        .foregroundStyle(state.softReminderLevel == .idle ? .orange : .yellow)
                        .padding(.top, 2)
                    Text(state.softReminderMessage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var levelColor: Color {
        switch state.level {
        case .fully: return .green
        case .wandering: return .yellow
        case .distracted: return .red
        case .idle: return .gray
        case nil: return .blue
        }
    }

    private var levelLabel: String {
        switch state.level {
        case .fully: return L("专注")
        case .wandering: return L("走神")
        case .distracted: return L("分心")
        case .idle: return L("空闲")
        case nil: return L("等待")
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - 时间线条

/// 时间线条——把 session 全长**固定切成 binCount 格**，每格按时序对应一段时间，
/// 取段内众数 level 上色。
///
/// 设计决策：
/// - **固定 60 格**：粗细不随会话长短抖动，60min 会话 = 每格 1 分钟，25min 会话 = 每格 25 秒
/// - **粗细统一**：所有竖线都是 2pt 宽、14pt 高，不靠高度差区分 idle，靠颜色饱和度
/// - **未到的格也画**：浅灰可见（white opacity 0.18），让 session 总长视觉成形
/// - hover：用全局 onContinuousHover 跟踪鼠标 X，按比例反推 bin index，
///   在 bar 上方浮一个气泡显示绝对时间 + 状态（一个 view 覆盖所有 hit-test，
///   不给每格挂 onHover——60 view 会爆 hit-test 开销）
struct FocusTimelineBar: View {
    let timeline: [TimelineEntry]
    let sessionStart: Date?
    let plannedDuration: TimeInterval
    let now: Date

    @State private var hoverX: CGFloat? = nil

    /// 固定 60 格——不管 session 25min 还是 120min 都画 60 条线
    private static let binCount: Int = 60

    /// 每格宽度（pt）——固定细线
    private static let lineWidth: CGFloat = 2

    /// 每格高度（pt）
    private static let lineHeight: CGFloat = 14

    /// 单格代表的时长（秒）。25min session → 25s/格；60min → 60s/格
    private var binSize: TimeInterval {
        plannedDuration / Double(Self.binCount)
    }

    /// 已经过的格数——决定哪些格上色、哪些当未来
    private var elapsedBinCount: Int {
        guard let start = sessionStart, binSize > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return max(0, min(Self.binCount, Int(ceil(elapsed / binSize))))
    }

    /// 取第 i 格的众数 level（无数据返回 nil）。
    /// 平票时按"严重性"固定 tie-break（distracted > wandering > idle > fully）——
    /// Dictionary.max 在 value 相同时 iteration 顺序不稳定，会导致同一格在每次
    /// SwiftUI re-render 颜色随机切换。让警示信号优先显示更贴合监督语义。
    private func dominantLevel(for binIndex: Int) -> FocusLevel? {
        guard let start = sessionStart else { return nil }
        let binStart = start.addingTimeInterval(Double(binIndex) * binSize)
        let binEnd = binStart.addingTimeInterval(binSize)
        var counts: [FocusLevel: Int] = [:]
        for entry in timeline where entry.timestamp >= binStart && entry.timestamp < binEnd {
            counts[entry.level, default: 0] += 1
        }
        return counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return Self.tieBreakRank(lhs.key) > Self.tieBreakRank(rhs.key)
        })?.key
    }

    /// 平票排序权重——数字越小越优先。配合 max(by:) 的 `>` 比较取最优先的。
    private static func tieBreakRank(_ level: FocusLevel) -> Int {
        switch level {
        case .distracted: return 0
        case .wandering:  return 1
        case .idle:       return 2
        case .fully:      return 3
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 60 条等粗竖线，间距由 Spacer 自动均布
                HStack(spacing: 0) {
                    ForEach(0..<Self.binCount, id: \.self) { i in
                        if i > 0 { Spacer(minLength: 0) }
                        binLine(index: i)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                // 顶层 hover 气泡
                if let x = hoverX, geo.size.width > 0 {
                    hoverTooltip(at: x, totalWidth: geo.size.width)
                }
            }
            .contentShape(.rect)  // hover 命中整片区域，不止彩条本体
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    if p.x >= 0 && p.x <= geo.size.width && p.y >= 0 && p.y <= geo.size.height {
                        hoverX = p.x
                    } else {
                        hoverX = nil
                    }
                case .ended:
                    hoverX = nil
                }
            }
        }
    }

    // MARK: 格子渲染

    @ViewBuilder
    private func binLine(index: Int) -> some View {
        let isElapsed = index < elapsedBinCount
        let level = isElapsed ? dominantLevel(for: index) : nil
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(cellColor(level: level, isElapsed: isElapsed))
            .frame(width: Self.lineWidth, height: Self.lineHeight)
    }

    private func cellColor(level: FocusLevel?, isElapsed: Bool) -> Color {
        // 未到：浅灰但可见，让 session 总长清晰可读
        guard isElapsed else { return Color.white.opacity(0.18) }
        switch level {
        case .fully:      return .green
        case .wandering:  return .yellow
        case .distracted: return .red
        case .idle:       return Color.white.opacity(0.45)   // 比未到亮，区分"已经过但空闲"
        case .none:       return Color.white.opacity(0.3)    // 已经过但没数据（极少见）
        }
    }

    // MARK: hover 气泡

    private func hoverTooltip(at x: CGFloat, totalWidth: CGFloat) -> some View {
        let binIndex = currentBinIndex(at: x, totalWidth: totalWidth)
        let label = tooltipLabel(forBin: binIndex)
        // 气泡宽度估算 ~88pt，避免贴边时溢出 panel
        let tooltipW: CGFloat = 88
        let clampedX = max(0, min(totalWidth - tooltipW, x - tooltipW / 2))
        return Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.85), in: .capsule)
            .overlay(
                Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .frame(width: tooltipW)
            .offset(x: clampedX, y: -2)
            .allowsHitTesting(false)
    }

    private func currentBinIndex(at x: CGFloat, totalWidth: CGFloat) -> Int {
        guard totalWidth > 0 else { return 0 }
        let frac = x / totalWidth
        return min(Self.binCount - 1, max(0, Int(frac * CGFloat(Self.binCount))))
    }

    private func tooltipLabel(forBin index: Int) -> String {
        guard let start = sessionStart else { return "" }
        let binStart = start.addingTimeInterval(Double(index) * binSize)
        let timeStr = Self.timeFormatter.string(from: binStart)
        let isElapsed = index < elapsedBinCount
        if !isElapsed {
            // 未到只显示时间，不挂状态后缀（没发生的事不要"未到"这种废话）
            return timeStr
        }
        let level = dominantLevel(for: index)
        let stateText: String
        switch level {
        case .fully:      stateText = L("专注")
        case .wandering:  stateText = L("走神")
        case .distracted: stateText = L("分心")
        case .idle:       stateText = L("空闲")
        case .none:       stateText = L("无数据")
        }
        return "\(timeStr) · \(stateText)"
    }

    /// HH:mm 格式化器——避免每次重建 DateFormatter
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - 进度圆环

/// 折叠态右端用的剩余时间圆环。progress 0~1，从满到空逆时针消减。
struct ProgressRing: View {
    let progress: Double   // 1 = 满；0 = 空
    let color: Color
    let size: CGFloat
    var lineWidth: CGFloat = 2.4

    var body: some View {
        ZStack {
            // 底环（淡色）
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            // 进度环（从 12 点位置顺时针绘制剩余比例）
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: progress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview("折叠态 · fully") {
    let state = NotchTimer.shared
    state.remaining = 1234
    state.planned = 1500
    state.level = .fully
    state.promise = "完成 Vigil 项目刘海调优"
    state.reasoning = "正在 Xcode 编辑 NotchTimer.swift 的圆环组件"
    return NotchView(state: state, controller: NotchIslandController(state: state))
        .background(Color.blue.opacity(0.2))
}

#Preview("展开态 · distracted") {
    let state = NotchTimer.shared
    state.remaining = 600
    state.planned = 1500
    state.level = .distracted
    state.promise = "完成 Vigil 项目"
    state.reasoning = "正在浏览 YouTube 推荐视频"
    state.reminder = "刚才在刷 YouTube；回到调试圆环吧"
    state.forceExpandUntil = Date().addingTimeInterval(60)
    return NotchView(state: state, controller: NotchIslandController(state: state))
        .background(Color.blue.opacity(0.2))
}
