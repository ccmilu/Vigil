import AppKit
import SwiftUI

/// 屏幕顶部居中的浮动小窗，显示倒计时 + 当前 level 颜色点。
/// session running 时显示；其它阶段隐藏。
/// 在带刘海的 MacBook 上正好坐在刘海下方；普通显示器贴菜单栏下沿。
@MainActor
final class NotchTimer {
    static let shared = NotchTimer()

    private var window: NSPanel?
    private var hostingController: NSHostingController<NotchTimerView>?
    private var state = NotchTimerState()

    private init() {}

    func show() {
        if window != nil { return }
        let host = NSHostingController(rootView: NotchTimerView(state: state))
        let size = NSSize(width: 180, height: 32)

        let panel = FloatingNotchPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false  // 允许点击聚焦主窗口
        panel.contentViewController = host
        panel.acceptsMouseMovedEvents = true

        hostingController = host
        window = panel
        positionAtNotch(panel: panel, size: size)
        panel.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        hostingController = nil
    }

    /// 上层 SessionManager 调用
    func update(remaining: TimeInterval, level: FocusLevel?) {
        state.remaining = remaining
        state.level = level
    }

    private func positionAtNotch(panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        // 顶部居中；菜单栏下 2pt。有刘海时菜单栏更厚，刚好坐刘海下沿
        let menuBarH: CGFloat = screen.safeAreaInsets.top  // 含刘海高
        let y = frame.maxY - menuBarH - size.height - 2
        let x = frame.midX - size.width / 2
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }
}

/// borderless panel 默认不能成为 key window；这里也不需要 key
private final class FloatingNotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 观察对象：让 SessionManager 改这俩字段时 SwiftUI 自动刷新
@MainActor
final class NotchTimerState: ObservableObject {
    @Published var remaining: TimeInterval = 0
    @Published var level: FocusLevel? = nil
}

struct NotchTimerView: View {
    @ObservedObject var state: NotchTimerState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
            Text(formatTime(state.remaining))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.78), in: .capsule)
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .onTapGesture {
            // 点一下把主窗口拉到前台
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.title == "Focus" {
                w.makeKeyAndOrderFront(nil)
            }
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
