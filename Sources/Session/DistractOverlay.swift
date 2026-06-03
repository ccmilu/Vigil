import AppKit
import SwiftUI

/// 分心时全屏覆盖一层半透明黑色，居中显示 AI 的 reminder 文字 + "返回工作"按钮。
///
/// 行为：
/// - distracted 跳变时调 present()；自动 8 秒后渐隐
/// - 点击/按 ESC 提前关闭
/// - 不强占焦点（用户仍可操作其它 App，但视觉上无法忽略）
@MainActor
final class DistractOverlay {
    static let shared = DistractOverlay()

    private var window: NSWindow?
    private var autoCloseTask: Task<Void, Never>?

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
            try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { self?.dismiss() }
            }
        }
    }

    func dismiss() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        window?.orderOut(nil)
        window?.contentViewController = nil
        window = nil
    }
}

private struct DistractOverlayView: View {
    let reminder: String
    let promise: String
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("回来一下")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text("当前承诺：\(promise)")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))

                Text(reminder.isEmpty ? "似乎偏离了承诺。回到正事？" : reminder)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 720)
                    .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 12))

                Button {
                    onDismiss()
                } label: {
                    Text("我回来了")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Text("8 秒后自动消失 · 点空白也可关闭")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(40)
            .scaleEffect(appeared ? 1 : 0.95)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: appeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
        .background(EscKeyHandler { onDismiss() })
    }
}

/// 监听 ESC 键的隐藏组件
private struct EscKeyHandler: NSViewRepresentable {
    let onEsc: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = EscView()
        v.onEsc = onEsc
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class EscView: NSView {
        var onEsc: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {  // ESC
                onEsc?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
