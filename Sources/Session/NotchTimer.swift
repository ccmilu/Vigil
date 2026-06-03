import AppKit
import SwiftUI

/// Dynamic Island 风格的刘海岛。
/// - 折叠态：紧贴菜单栏顶部，宽度匹配刘海，仅 level 圆点 + Focus 标签
/// - 展开态（hover / distracted 触发）：变宽变高，显示倒计时 + reminder
/// - 平滑形变动画（spring）
@MainActor
final class NotchTimer: ObservableObject {
    static let shared = NotchTimer()

    @Published var remaining: TimeInterval = 0
    @Published var level: FocusLevel? = nil
    @Published var promise: String = ""
    @Published var reminder: String = ""
    /// distracted 跳变时强制展开到这个时刻
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

    /// 检测到 distracted 跳变时召唤强制展开 6 秒
    func flashDistracted(reminder: String) {
        self.reminder = reminder
        self.forceExpandUntil = Date().addingTimeInterval(6)
    }

    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: NotchView.maxWidth + 40, height: NotchView.maxHeight + 4)
        // 屏幕顶部居中；最高点贴齐屏幕顶部（盖住菜单栏中间区域）
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height
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

    // 折叠态尺寸（匹配 14" 刘海宽度）
    static let collapsedWidth: CGFloat = 200
    static let collapsedHeight: CGFloat = 30
    // 展开态尺寸
    static let maxWidth: CGFloat = 480
    static let maxHeight: CGFloat = 140

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(width: Self.maxWidth + 40, height: Self.maxHeight + 4)
        // 用一个低频 timer 检查 forceExpandUntil 是否还在生效
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
        }
    }

    private var isExpanded: Bool {
        if hovering { return true }
        if let until = state.forceExpandUntil, until > now { return true }
        return false
    }

    private var island: some View {
        ZStack {
            // 黑色岛形状
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 22,
                bottomTrailingRadius: 22,
                topTrailingRadius: 0
            )
            .fill(.black)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22,
                    topTrailingRadius: 0
                )
                .stroke(borderColor, lineWidth: 1.5)
            )

            // 内容层
            Group {
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    collapsedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isExpanded)
        }
        .frame(
            width: isExpanded ? Self.maxWidth : Self.collapsedWidth,
            height: isExpanded ? Self.maxHeight : Self.collapsedHeight
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: isExpanded)
        .onHover { hovering = $0 }
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.title == "Focus" {
                w.makeKeyAndOrderFront(nil)
            }
        }
        // distracted 时给一圈红色脉动描边
        .overlay(distractedPulse)
    }

    private var collapsedContent: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
            Text(formatTime(state.remaining))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(levelColor)
                    .frame(width: 12, height: 12)
                Text(formatTime(state.remaining))
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer()
                Text(levelLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(levelColor.opacity(0.15), in: .capsule)
            }
            if !state.promise.isEmpty {
                Text(state.promise)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            if isDistracted, !state.reminder.isEmpty {
                Text(state.reminder)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var distractedPulse: some View {
        Group {
            if isDistracted {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22,
                    topTrailingRadius: 0
                )
                .stroke(Color.red.opacity(0.6), lineWidth: 2)
                .blur(radius: 0.5)
            }
        }
    }

    private var isDistracted: Bool { state.level == .distracted }

    private var borderColor: Color {
        switch state.level {
        case .distracted: return Color.red.opacity(0.4)
        case .fully: return Color.white.opacity(0.08)
        default: return Color.white.opacity(0.06)
        }
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
