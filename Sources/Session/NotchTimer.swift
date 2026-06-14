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
/// 由 `NotchTimer.islandGeometry` 统一计算，三处调用方（currentIslandRect /
/// NotchView / createWindow）都从这里读，不再各自重复 autoDetect 分支逻辑。
struct IslandGeometry {
    /// 折叠态尺寸（宽 = 内容驱动；高 = 菜单栏高度）
    let collapsed: CGSize
    /// 展开态尺寸（宽 = notchWidth + 两侧扩展；高 = NotchStyle.expandedHeight）
    let expanded: CGSize
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

    /// 鼠标是否在岛上 hover——存这里让 PassthroughHostingView 能 query 算 hit rect
    @Published var hovering: Bool = false

    /// 本次会话起始时间——TimelineBar 算 bin 边界用绝对时间。
    /// show() 时设，hide() 时清。
    @Published var sessionStart: Date? = nil

    /// 已经发生的分析点序列，按时间升序追加。
    /// 长度上限：planned/captureInterval（约 720 for 60min @5s）；不裁剪即可。
    @Published var timeline: [TimelineEntry] = []

    private var window: NSPanel?
    private var mouseLocalMonitor: Any?
    private var mouseGlobalMonitor: Any?
    private var hoverPollTimer: Timer?

    private init() {}

    func show(promise: String, plannedSeconds: Int) {
        self.promise = promise
        self.planned = TimeInterval(plannedSeconds)
        // 重置 timeline——上一次会话残留数据不能复用到本次
        self.sessionStart = Date()
        self.timeline.removeAll()
        if window == nil { createWindow() }
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        forceExpandUntil = nil
        sessionStart = nil
        timeline.removeAll()
        stopMouseTracking()
    }

    /// SessionManager 每写一条 AnalysisRecord 就调一次，按 createdAt 追加。
    /// 顺序由调用方保证（5s tick 串行）；这里不做去重 / 排序。
    func appendAnalysis(at timestamp: Date, level: FocusLevel) {
        timeline.append(TimelineEntry(timestamp: timestamp, level: level))
    }

    private func stopMouseTracking() {
        if let m = mouseLocalMonitor { NSEvent.removeMonitor(m); mouseLocalMonitor = nil }
        if let m = mouseGlobalMonitor { NSEvent.removeMonitor(m); mouseGlobalMonitor = nil }
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
    }

    /// 用全局鼠标位置驱动 panel.ignoresMouseEvents：
    /// - 鼠标进入岛实际矩形 → panel 接收事件 + state.hovering=true（SwiftUI 展开）
    /// - 鼠标离开 → panel.ignoresMouseEvents=true 全穿透，下方应用能点击
    /// - forceExpandUntil 期间永远保持接收（不让用户错过软提醒）
    fileprivate func startMouseTracking() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in
            self?.refreshHoverState()
        }
        // Local: 鼠标在本 App 上（panel 接收事件时）
        mouseLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { event in
            handler(event); return event
        }
        // Global: 鼠标在其他 App 上（panel ignoresMouseEvents=true 期间穿透时）
        mouseGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { event in
            handler(event)
        }
        // 兜底轮询：mouseMoved 在鼠标停下后不再 fire（用户快速移到岛上停住就卡住），
        // 必须主动轮询。注意 RunLoop mode：
        // - scheduledTimer 默认只在 .default 跑，鼠标快速移动时会切到 .eventTracking，Timer 暂停
        // - 用 .common 包含 default + eventTracking + modal，任何模式都跑
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.refreshHoverState()
        }
        RunLoop.main.add(t, forMode: .common)
        hoverPollTimer = t
    }

    private func refreshHoverState() {
        guard let panel = window else { return }
        let mouseGlobal = NSEvent.mouseLocation
        let panelFrame = panel.frame

        // currentIslandRect 返回 panel-local (isFlipped=false 时 y 向上)
        let islandLocal = currentIslandRect(in: panelFrame.size, isFlipped: false)
        // 转全局 (NSScreen) 坐标
        let islandGlobal = NSRect(
            x: panelFrame.origin.x + islandLocal.minX,
            y: panelFrame.origin.y + islandLocal.minY,
            width: islandLocal.width,
            height: islandLocal.height
        )
        // hot zone 各边扩展 4pt：
        // - NSRect.contains 是半开区间 [min, max)，鼠标 y=screen.frame.maxY 时刚好等于
        //   islandGlobal.maxY 不算命中——屏幕物理顶卡死
        // - 物理刘海机型上鼠标在刘海区会被 macOS 略微钳制，几像素误差
        let hotZone = islandGlobal.insetBy(dx: -4, dy: -4)
        let inside = hotZone.contains(mouseGlobal)

        // forceExpand 期间（distract 红色描边 / idle 持续展开）保持接收点击
        let forceExpanded = (forceExpandUntil ?? .distantPast) > Date()

        let shouldReceive = inside || forceExpanded
        if panel.ignoresMouseEvents != !shouldReceive {
            panel.ignoresMouseEvents = !shouldReceive
        }
        if hovering != inside {
            hovering = inside
        }
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

    /// 当前岛实际矩形。
    /// - panelSize: NSHostingView.bounds.size
    /// - isFlipped: NSHostingView.isFlipped — true 时 y=0 是顶，false 时 y=0 是底
    /// PassthroughHostingView.hitTest 用这个判断鼠标点是否在岛上，
    /// 岛外区域返回 nil 让点击穿透到下方应用。
    func currentIslandRect(in panelSize: NSSize, isFlipped: Bool = true) -> NSRect {
        let isExpanded = hovering || (forceExpandUntil.map { $0 > Date() } ?? false)
        // 不再下移：菜单栏区有了 timer/status 内容后，3pt 偏移变成可见空隙，
        // 接受顶部 concave 角点 1pt stroke 被屏幕顶截掉的代价（曲线本体在 y≥0 内不受影响）
        let topInset: CGFloat = 0

        // 从单一来源读岛尺寸，不再各算各的
        let geo = islandGeometry
        let islandSize = isExpanded ? geo.expanded : geo.collapsed

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

    /// 折叠 / 展开几何尺寸的单一来源。
    ///
    /// currentIslandRect、NotchView 的宽高属性、createWindow 的 panel 初始尺寸
    /// 都从这里读，保证三处数字完全一致，改参数只需改 NotchStyle 常量一处。
    var islandGeometry: IslandGeometry {
        let collapsedW: CGFloat
        let collapsedH: CGFloat
        let expandedW: CGFloat

        if NotchStyle.autoDetect {
            // 折叠态：两侧 padding + 左端 level 图标 + 物理刘海宽 + 右端进度圆环
            let sidePad = max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6
            collapsedW = sidePad + NotchStyle.levelIconSize
                       + (ScreenMetrics.notchWidth + NotchStyle.collapsedMiddleExtra)
                       + NotchStyle.progressRingSize + sidePad
            // 折叠态高度跟随菜单栏
            collapsedH = ScreenMetrics.menuBarHeight
            // 展开态：物理刘海宽 + 两侧各扩展 expandedSideExtension
            expandedW = ScreenMetrics.notchWidth + 2 * NotchStyle.expandedSideExtension
        } else {
            collapsedW = NotchStyle.manualCollapsedWidth
            collapsedH = NotchStyle.manualCollapsedHeight
            expandedW  = NotchStyle.manualExpandedWidth
        }

        return IslandGeometry(
            collapsed: CGSize(width: collapsedW, height: collapsedH),
            expanded:  CGSize(width: expandedW,  height: NotchStyle.expandedHeight)
        )
    }

    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        // panel 尺寸用 expanded 上限做窗口大小；岛在内部居中缩放
        // 从单一来源读展开态宽度，与 currentIslandRect / NotchView 保持一致
        let maxExpandedW = islandGeometry.expanded.width
        let panelW = maxExpandedW + 40
        let panelH = NotchStyle.expandedHeight + 8
        let origin = NSPoint(
            x: screen.frame.midX - panelW / 2,
            y: screen.frame.maxY - panelH  // 顶贴菜单栏（仅折叠态贴顶；展开态由 VStack padding 下移）
        )
        let panel = FloatingNotchPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: panelW, height: panelH)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        // 默认全穿透——下方应用的点击不被拦截
        // 通过 startMouseTracking() 的 NSEvent 全局监听动态切换：
        // 鼠标进入岛矩形时 ignoresMouseEvents=false 才接收点击/hover
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        // 用透明 hit-test 的 NSHostingView 而不是默认的 NSHostingController：
        // NSHostingView 默认 hitTest 在空白区域返回 self（NSPanel 整块吃事件），
        // 折叠态岛只占很小一块但 panel 矩形 440×158 全部拦截下方点击。
        // PassthroughHostingView 让 SwiftUI 子视图没命中时返回 nil → 事件穿透。
        let host = PassthroughHostingView(rootView: NotchView(state: self))
        host.frame = NSRect(origin: .zero, size: NSSize(width: panelW, height: panelH))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        window = panel
        startMouseTracking()
    }
}

private final class FloatingNotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// hitTest 行为修正：直接拿 NotchTimer 算出的当前岛矩形过滤鼠标命中。
/// 岛之外的整块 panel 区域返回 nil，事件穿透到下方应用。
/// SwiftUI 默认会让 panel 整个 frame 接收 hit-test（即使透明），所以必须在
/// NSView 层主动拦截，不能只靠 SwiftUI 自己的 hit-test 推断。
/// hitTest 兜底：panel.ignoresMouseEvents 已经控制了"事件是否进入 panel"的整体行为，
/// 这里再加一层 view-local 过滤——避免极端情况下（global monitor 来不及更新）
/// 点击穿过岛旁边的透明区域命中 self
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let islandRect = NotchTimer.shared.currentIslandRect(in: bounds.size, isFlipped: isFlipped)
        guard islandRect.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - View

struct NotchView: View {
    @ObservedObject var state: NotchTimer
    @State private var now = Date()
    private var hovering: Bool { state.hovering }

    /// 从单一来源读岛尺寸，避免与 currentIslandRect / createWindow 各自重复计算。
    private var geo: IslandGeometry { state.islandGeometry }

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
            state.hovering = isHovering
            // 用户 hover 到岛 = 已经"看到提醒"，立刻清掉强制展开 + 停 idle/wandering 软提醒
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
            Spacer(minLength: 0)
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
                .frame(height: ScreenMetrics.menuBarHeight)
            bottomContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 顶行三段式（mirror 折叠态：左 level 图标 / 右进度圆环 → 左状态 capsule / 右 timer）
    /// 三段宽度合计 = expandedSideExtension + notchWidth + expandedSideExtension = 展开总宽
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

            // 中间——物理刘海占位，不画内容
            Color.clear.frame(width: ScreenMetrics.notchWidth)

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
    return NotchView(state: state)
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
    return NotchView(state: state)
        .background(Color.blue.opacity(0.2))
}
