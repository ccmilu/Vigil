import AppKit
import SwiftUI

/// 分心时全屏覆盖一层半透明黑色，居中显示 AI 的 reminder 文字 + "返回工作"按钮。
///
/// 行为：
/// - distracted 跳变时调 present()；自动 30 秒后渐隐
/// - 只能通过"我回来了"按钮主动关闭（ESC、空白处不行）—— 强化"必须确认"的仪式感
/// - 不强占焦点（用户仍可操作其它 App，但视觉上无法忽略）
@MainActor
final class DistractOverlay {
    static let shared = DistractOverlay()

    private var window: NSWindow?
    private var autoCloseTask: Task<Void, Never>?
    /// 外部监听 overlay 真正关闭的回调（点按钮 / 自动关 / 主动 dismiss 都会触发）。
    /// FocusSessionManager 用它把"持续分心 30s 再弹"的计时基准从弹窗瞬间挪到关闭瞬间。
    var onClosed: (() -> Void)?

    /// 设置开关：用户可以在 Settings 关掉这个体验
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "overlay.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "overlay.enabled") }
    }

    private init() {}

    func present(reminder: String, promise: String) {
        guard enabled else { return }
        dismiss()
        guard let screen = NSScreen.main else { return }

        // 用 NSPanel + 全屏覆盖；NSScreen.frame 已含菜单栏，但 setFrame 后内容会自动撑满
        let w = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = NSWindow.Level(Int(CGShieldingWindowLevel()))  // 高于一切 App
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = false
        w.isMovable = false
        w.setFrame(screen.frame, display: false)

        let host = NSHostingController(
            rootView: DistractOverlayView(
                reminder: reminder,
                promise: promise,
                onDismiss: { [weak self] in self?.dismiss() }
            )
        )
        host.view.frame = NSRect(origin: .zero, size: screen.frame.size)
        host.view.autoresizingMask = [.width, .height]
        w.contentViewController = host
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w

        autoCloseTask?.cancel()
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { self?.dismiss() }
            }
        }
    }

    func dismiss() {
        let wasShown = (window != nil)
        autoCloseTask?.cancel()
        autoCloseTask = nil
        window?.orderOut(nil)
        window?.contentViewController = nil
        window = nil
        if wasShown { onClosed?() }
    }
}

private struct DistractOverlayView: View {
    let reminder: String
    let promise: String
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // 底层稍微透出桌面，给玻璃下方留点可被折射的内容
            Color.black.opacity(0.55)

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("回来一下")
                    .font(.system(size: 32, weight: .bold))

                Text("当前承诺：\(promise)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(reminder.isEmpty ? "似乎偏离了承诺。回到正事？" : reminder)
                    .font(.system(size: 20, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 640)

                Button {
                    onDismiss()
                } label: {
                    Text("我回来了")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(.orange, in: .capsule)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Text("点击「我回来了」返回 · 30 秒后自动消失")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)
            .frame(maxWidth: 720)
            .liquidGlass(
                in: .rect(cornerRadius: 28),
                tint: .orange.opacity(0.08),
                intensity: .prominent
            )
            .scaleEffect(appeared ? 1 : 0.95)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: appeared)
        }
        // 让玻璃浮卡内 .primary / .secondary 自动变亮色，避免在暗底上看不清；
        // 比手写 .white.opacity(...) 更符合 HIG 的"语义颜色 + 系统适应"
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }
}
