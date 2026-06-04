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
    static let progressRingSize: CGFloat = 22
    /// 折叠态圆环描边宽度（Apple Watch 运动圆环感觉，越大越"实"）
    static let progressRingLineWidth: CGFloat = 4
    /// 折叠态左端 level 状态图标大小
    static let levelIconSize: CGFloat = 14

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

// MARK: - 状态

/// 软提醒级别——distract 之外的两种轻量提示。
/// 决定刘海描边色 + 文案样式；distract 仍由 state.level == .distracted 判断（最高优先级）。
enum SoftReminderLevel {
    case none
    case wandering   // 持续走神，黄色描边 + 12s 展开
    case idle        // 长时间不在电脑前，橙色描边 + 持续展开 + 周期声音
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

    private var window: NSPanel?

    private init() {}

    func show(promise: String, plannedSeconds: Int) {
        self.promise = promise
        self.planned = TimeInterval(plannedSeconds)
        if window == nil { createWindow() }
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        forceExpandUntil = nil
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

    /// 当前岛实际矩形（panel 内坐标，SwiftUI 习惯：y 向下，0=顶）。
    /// PassthroughHostingView.hitTest 用这个判断鼠标点是否在岛上，
    /// 岛外区域返回 nil 让点击穿透到下方应用。
    func currentIslandRect(in panelSize: NSSize) -> NSRect {
        let isExpanded = hovering || (forceExpandUntil.map { $0 > Date() } ?? false)
        // 软/强提醒展开态会下移 NotchStyle.distractedBorderWidth+1，对应 SwiftUI VStack 的 padding.top
        let isStrongAlert = level == .distracted
        let isSoftAlert = softReminderLevel != .none
        let topInset: CGFloat = (isExpanded && (isStrongAlert || isSoftAlert)) ? NotchStyle.distractedBorderWidth + 1 : 0

        // 岛宽：折叠 / 展开各自的 content-driven 宽度
        let islandW: CGFloat
        let islandH: CGFloat
        if isExpanded {
            if NotchStyle.autoDetect {
                islandW = ScreenMetrics.notchWidth + 2 * NotchStyle.expandedSideExtension
            } else {
                islandW = NotchStyle.manualExpandedWidth
            }
            islandH = NotchStyle.expandedHeight
        } else {
            if NotchStyle.autoDetect {
                let sidePad = max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6
                let leftW = NotchStyle.levelIconSize
                let rightW = NotchStyle.progressRingSize
                let middle = ScreenMetrics.notchWidth + NotchStyle.collapsedMiddleExtra
                islandW = sidePad + leftW + middle + rightW + sidePad
                islandH = ScreenMetrics.menuBarHeight
            } else {
                islandW = NotchStyle.manualCollapsedWidth
                islandH = NotchStyle.manualCollapsedHeight
            }
        }
        let x = (panelSize.width - islandW) / 2
        let y = topInset
        return NSRect(x: x, y: y, width: islandW, height: islandH)
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

    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        // panel 尺寸用 expanded 上限做窗口大小；岛在内部居中缩放
        let maxExpandedW: CGFloat
        if NotchStyle.autoDetect {
            maxExpandedW = ScreenMetrics.notchWidth + 2 * NotchStyle.expandedSideExtension
        } else {
            maxExpandedW = NotchStyle.manualExpandedWidth
        }
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
        panel.ignoresMouseEvents = false
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
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // NSHostingView isFlipped=true，point.y=0 是 view 顶；和 NotchView 内 VStack 顶对齐
        let islandRect = NotchTimer.shared.currentIslandRect(in: bounds.size)
        guard islandRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - View

struct NotchView: View {
    @ObservedObject var state: NotchTimer
    @State private var now = Date()
    private var hovering: Bool { state.hovering }

    /// 折叠态宽度：内容驱动 — 由实际 left/right 组件 + 刘海中央预留空白决定
    private var collapsedWidth: CGFloat {
        if NotchStyle.autoDetect {
            let sidePad = max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 6
            let leftW = NotchStyle.levelIconSize
            let rightW = NotchStyle.progressRingSize
            let middle = ScreenMetrics.notchWidth + NotchStyle.collapsedMiddleExtra
            return sidePad + leftW + middle + rightW + sidePad
        }
        return NotchStyle.manualCollapsedWidth
    }

    /// 展开态宽度：autoDetect 时也跟随物理刘海（避免硬编码在小刘海机型上过宽）
    private var expandedWidth: CGFloat {
        if NotchStyle.autoDetect {
            return ScreenMetrics.notchWidth + 2 * NotchStyle.expandedSideExtension
        }
        return NotchStyle.manualExpandedWidth
    }

    /// 折叠态高度：autoDetect 时跟随菜单栏高度
    private var collapsedHeight: CGFloat {
        NotchStyle.autoDetect ? ScreenMetrics.menuBarHeight : NotchStyle.manualCollapsedHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(
                    width: isExpanded ? expandedWidth : collapsedWidth,
                    height: isExpanded ? NotchStyle.expandedHeight : collapsedHeight
                )
                // 仅 distract 展开态下移：红色描边较粗（2pt），center-aligned 上半部分
                // 贴屏幕顶会被截掉，反向圆角看不到。其他状态描边细（0.5pt）不需要补偿。
                .padding(.top, (isExpanded && (isDistracted || isSoftAlert)) ? NotchStyle.distractedBorderWidth + 1 : 0)
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
            for w in NSApp.windows where w.title == "Focus" {
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

    /// 展开态时，岛上方 menuBarHeight 范围被物理刘海/菜单栏遮挡，
    /// 所有可读内容必须放在这条线下方。
    private var contentTopInset: CGFloat {
        // 留几 pt 让内容和"刘海下沿"有间距
        ScreenMetrics.menuBarHeight + 6
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(levelColor)
                    .frame(width: 12, height: 12)
                Text(formatTime(state.remaining))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer()
                Text(levelLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(levelColor.opacity(0.18), in: .capsule)
            }
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

            // AI 每帧的活动描述（fully/wandering/distracted 都显示）
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

            // distracted 时叠加 AI 写的 reminder（拉回文案）
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

            // idle / wandering 软提醒文案
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
        .padding(.top, contentTopInset)   // ← 把所有内容推到菜单栏下方
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
        case .fully: return "专注"
        case .wandering: return "走神"
        case .distracted: return "分心"
        case .idle: return "空闲"
        case nil: return "等待"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
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
    state.promise = "完成 Focus 项目刘海调优"
    state.reasoning = "正在 Xcode 编辑 NotchTimer.swift 的圆环组件"
    return NotchView(state: state)
        .background(Color.blue.opacity(0.2))
}

#Preview("展开态 · distracted") {
    let state = NotchTimer.shared
    state.remaining = 600
    state.planned = 1500
    state.level = .distracted
    state.promise = "完成 Focus 项目"
    state.reasoning = "正在浏览 YouTube 推荐视频"
    state.reminder = "刚才在刷 YouTube；回到调试圆环吧"
    state.forceExpandUntil = Date().addingTimeInterval(60)
    return NotchView(state: state)
        .background(Color.blue.opacity(0.2))
}
