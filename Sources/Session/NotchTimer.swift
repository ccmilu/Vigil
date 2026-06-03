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

    /// autoDetect 时，折叠态在物理刘海宽度基础上左右各扩展多少 pt（让内容可见）。
    /// 物理刘海中央会盖住岛中间区域，所以内容必须放在岛的最左 / 最右端、
    /// 也就是刘海两侧的扩展区里才能露出。
    ///
    /// 例如：刘海宽 220 + extension 100 → 岛总宽 420，左右各 100pt 可见区域。
    static let collapsedSideExtension: CGFloat = 80

    // ===== 手动尺寸（autoDetect=false 时生效）=====
    static let manualCollapsedWidth: CGFloat = 380
    static let manualCollapsedHeight: CGFloat = 32

    // ===== 展开态尺寸 =====
    static let expandedWidth: CGFloat = 560
    static let expandedHeight: CGFloat = 130

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
    static let distractedFlashSeconds: TimeInterval = 6

    enum ContentAlignment {
        case leading, trailing, center, split
    }
}

// MARK: - 状态

@MainActor
final class NotchTimer: ObservableObject {
    static let shared = NotchTimer()

    @Published var remaining: TimeInterval = 0
    @Published var level: FocusLevel? = nil
    @Published var promise: String = ""
    @Published var reminder: String = ""
    @Published var forceExpandUntil: Date? = nil

    private var window: NSPanel?

    private init() {}

    func show(promise: String) {
        self.promise = promise
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

    func flashDistracted(reminder: String) {
        self.reminder = reminder
        self.forceExpandUntil = Date().addingTimeInterval(NotchStyle.distractedFlashSeconds)
    }

    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        // panel 尺寸用 expanded 上限做窗口大小；岛在内部居中缩放
        let panelW = NotchStyle.expandedWidth + 40
        let panelH = NotchStyle.expandedHeight + 8
        let origin = NSPoint(
            x: screen.frame.midX - panelW / 2,
            y: screen.frame.maxY - panelH  // 顶贴菜单栏
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
        panel.contentViewController = NSHostingController(rootView: NotchView(state: self))
        window = panel
    }
}

private final class FloatingNotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

struct NotchView: View {
    @ObservedObject var state: NotchTimer
    @State private var hovering = false
    @State private var now = Date()

    /// 折叠态宽度：autoDetect 时 = 物理刘海宽 + 左右扩展（让内容能露出在刘海两侧）
    private var collapsedWidth: CGFloat {
        if NotchStyle.autoDetect {
            return ScreenMetrics.notchWidth + 2 * NotchStyle.collapsedSideExtension
        }
        return NotchStyle.manualCollapsedWidth
    }

    /// 折叠态高度：autoDetect 时跟随菜单栏高度
    private var collapsedHeight: CGFloat {
        NotchStyle.autoDetect ? ScreenMetrics.menuBarHeight : NotchStyle.manualCollapsedHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(
                    width: isExpanded ? NotchStyle.expandedWidth : collapsedWidth,
                    height: isExpanded ? NotchStyle.expandedHeight : collapsedHeight
                )
                .animation(
                    .spring(response: NotchStyle.springResponse, dampingFraction: NotchStyle.springDamping),
                    value: isExpanded
                )
            Spacer(minLength: 0)
        }
        .frame(width: NotchStyle.expandedWidth + 40, height: NotchStyle.expandedHeight + 8)
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

    /// 岛本体 — 反向圆角形状 + 描边 + 内容，共享同一 shape 保证缩放同步
    private var island: some View {
        ZStack {
            shape
                .fill(.black)
                // distracted 时画底部 U 形红色描边（顶部贴菜单栏，故意不画）；
                // 非 distracted 时画淡灰底色描边（也只画底部，保持视觉一致）
                .overlay(
                    NotchBottomBorder(
                        topCornerRadius: NotchStyle.topCornerRadius,
                        bottomCornerRadius: NotchStyle.bottomCornerRadius
                    )
                    .stroke(
                        isDistracted ? NotchStyle.distractedBorderColor : Color.white.opacity(0.08),
                        lineWidth: isDistracted ? NotchStyle.distractedBorderWidth : 0.5
                    )
                )
            content
        }
        .clipShape(shape)
        .onHover { hovering = $0 }
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

    // MARK: 折叠态内容

    private var collapsedContent: some View {
        Group {
            switch NotchStyle.collapsedContentAlignment {
            case .leading:
                HStack { collapsedItem; Spacer() }
            case .trailing:
                HStack { Spacer(); collapsedItem }
            case .center:
                collapsedItem
            case .split:
                HStack(spacing: 0) {
                    // 左端：level 圆点（在物理刘海左侧的扩展区）
                    Circle()
                        .fill(levelColor)
                        .frame(width: 8, height: 8)
                    Spacer()
                    // 右端：倒计时（在物理刘海右侧的扩展区）
                    Text(formatTime(state.remaining))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
        }
        // 贴近岛左右端（避开刘海中央），仅留少量边距让圆角不切到内容
        .padding(.horizontal, max(NotchStyle.topCornerRadius, NotchStyle.bottomCornerRadius) + 4)
        .padding(.bottom, 2)
    }

    private var collapsedItem: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)
            Text(formatTime(state.remaining))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    // MARK: 展开态内容

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
                Text(state.promise)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            if isDistracted, !state.reminder.isEmpty {
                Text(state.reminder)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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

// MARK: - Preview

#Preview("折叠态 · fully") {
    let state = NotchTimer.shared
    state.remaining = 1234
    state.level = .fully
    state.promise = "完成 Focus 项目刘海调优"
    return NotchView(state: state)
        .background(Color.blue.opacity(0.2))
}

#Preview("展开态 · distracted") {
    let state = NotchTimer.shared
    state.remaining = 1234
    state.level = .distracted
    state.promise = "完成 Focus 项目"
    state.reminder = "刚才在刷 YouTube；回到工作吧"
    state.forceExpandUntil = Date().addingTimeInterval(60)
    return NotchView(state: state)
        .background(Color.blue.opacity(0.2))
}
