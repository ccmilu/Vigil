import AppKit
import SwiftUI

// MARK: - ✏️ 你可以微调的参数都在这里

/// 调这些常量，然后用 Xcode 打开本文件，光标点进 `#Preview { ... }`，
/// 右上角 Editor → Canvas（或 ⌥⌘↩）打开预览。
/// 实时拖动 hovering / distracted 模拟两种状态。
enum NotchStyle {
    // MARK: 尺寸（高度尽量贴菜单栏）
    /// 折叠态宽度
    static let collapsedWidth: CGFloat = 360
    /// 折叠态高度 — 默认匹配 macOS 菜单栏高度
    static let collapsedHeight: CGFloat = 26

    /// 展开态宽度
    static let expandedWidth: CGFloat = 520
    /// 展开态高度（向菜单栏下方延伸）
    static let expandedHeight: CGFloat = 110

    // MARK: 形状圆角
    /// 顶部圆角（顶边贴菜单栏，给一点点圆滑）
    static let topCornerRadius: CGFloat = 6
    /// 底部圆角（不要太圆）
    static let bottomCornerRadius: CGFloat = 12

    // MARK: 位置
    /// 整个 NSPanel 的水平位置：在屏幕水平居中。
    /// 物理刘海大约从屏幕中央左右各 110pt（约 220pt 宽），
    /// 所以岛的宽度建议 > 220 让左右两端伸出刘海，内容才看得见。
    static let horizontalCenter = true

    /// 顶部 Y 偏移（pt）：0 = 紧贴屏幕最顶部（盖菜单栏中央）；
    /// 正值 = 向下挪一点。
    static let topOffset: CGFloat = 0

    // MARK: 内容布局（避开物理刘海中央摄像头区域）
    /// 折叠态内容贴向岛的哪一侧：
    /// - .leading 显示在岛左端（露出刘海左边）
    /// - .trailing 显示在岛右端（露出刘海右边）
    /// - .center 显示在岛中央（会被刘海遮住一部分）
    /// - .split 倒计时在左端 + level 圆点在右端
    static let collapsedContentAlignment: ContentAlignment = .split

    // MARK: distracted 红色描边
    static let distractedBorderWidth: CGFloat = 2.0
    static let distractedBorderColor: Color = .red

    // MARK: 动画
    /// 形变 spring 参数
    static let springResponse: Double = 0.42
    static let springDamping: Double = 0.78

    /// distracted 跳变时强制展开的秒数
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
        // 用 expanded 尺寸作为 panel 大小（折叠态居中放在里面）
        let size = NSSize(width: NotchStyle.expandedWidth + 40, height: NotchStyle.expandedHeight + 8)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - NotchStyle.topOffset
        )
        let panel = FloatingNotchPanel(
            contentRect: NSRect(origin: origin, size: size),
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

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(
                    width: isExpanded ? NotchStyle.expandedWidth : NotchStyle.collapsedWidth,
                    height: isExpanded ? NotchStyle.expandedHeight : NotchStyle.collapsedHeight
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

    /// 岛本体 — 黑色背景 + 描边都画在同一形状里，保证缩放完全同步
    private var island: some View {
        ZStack {
            shape
                .fill(.black)
                .overlay(
                    // 描边在 fill 之上叠加，share 同一份 frame
                    shape.stroke(
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

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: NotchStyle.topCornerRadius,
            bottomLeadingRadius: NotchStyle.bottomCornerRadius,
            bottomTrailingRadius: NotchStyle.bottomCornerRadius,
            topTrailingRadius: NotchStyle.topCornerRadius
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
                HStack {
                    collapsedItem
                    Spacer()
                }
            case .trailing:
                HStack {
                    Spacer()
                    collapsedItem
                }
            case .center:
                collapsedItem
            case .split:
                HStack {
                    // 左端：level 圆点
                    Circle()
                        .fill(levelColor)
                        .frame(width: 8, height: 8)
                    Spacer()
                    // 右端：倒计时
                    Text(formatTime(state.remaining))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var collapsedItem: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
            Text(formatTime(state.remaining))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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

// MARK: - Preview（Xcode Canvas 实时预览）

#Preview("折叠态 · fully") {
    let state = NotchTimer.shared
    state.remaining = 1234
    state.level = .fully
    state.promise = "完成 Focus 项目刘海调优"
    return NotchView(state: state)
        .frame(width: 600, height: 200)
        .background(Color.blue.opacity(0.2))
}

#Preview("折叠态 · distracted") {
    let state = NotchTimer.shared
    state.remaining = 1234
    state.level = .distracted
    state.promise = "完成 Focus 项目"
    state.reminder = "刚才在刷 YouTube；回到工作吧"
    return NotchView(state: state)
        .frame(width: 600, height: 200)
        .background(Color.blue.opacity(0.2))
}
