import AppKit
import OSLog
import SwiftUI

/// 分心时全屏覆盖一层半透明黑色，居中显示 AI 的 reminder 文字 + "返回工作"按钮。
///
/// 行为：
/// - distracted 跳变时调 present()；自动 30 秒后渐隐
/// - 只能通过"我回来了"按钮主动关闭（ESC、空白处不行）—— 强化"必须确认"的仪式感
/// - 不强占焦点（用户仍可操作其它 App，但视觉上无法忽略）
/// - 多屏：每块显示器各盖一份遮罩，任一屏点按钮 → 全部屏一起关
@MainActor
final class DistractOverlay {
    static let shared = DistractOverlay()

    /// 每块屏一个全屏 panel，key 为 displayID
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    /// 最近一次 present 的内容，供屏幕热插拔时按原样重建遮罩
    private var lastPayload: (reminder: String, promise: String, showSuppress: Bool)?
    private var autoCloseTask: Task<Void, Never>?
    /// 屏幕参数变化（热插拔 / 分辨率 / 排列）通知的观察 token——随 singleton 生命周期，无需手动移除
    private var screenParamsObserver: NSObjectProtocol?
    /// 热插拔 0.3s 合并防抖任务——新通知到来时取消上一个，只重建最后一次
    private var screenChangeDebounceTask: Task<Void, Never>?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Vigil", category: "DistractOverlay")
    /// 本次提醒生命周期结束的回调：点按钮 / 自动关 / 主动 dismiss，
    /// 以及"应当弹出/维持但一块屏都没盖上"的零屏路径（R1）都会触发，恰好一次。
    /// FocusSessionManager 在 present 前把 cooldown 推到 distantFuture，全靠这个回调
    /// 恢复计时——任何路径漏 fire 都会让该段 distract 提醒被永久静默。
    var onClosed: (() -> Void)?
    /// "本次分心别再弹"按钮的回调。仅当 present(showSuppress: true) 时显示。
    var onSuppress: (() -> Void)?

    /// 设置开关：用户可以在 Settings 关掉这个体验
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "overlay.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "overlay.enabled") }
    }

    private init() {
        // 屏幕热插拔 / 分辨率变化监听（与 NotchTimer 各自独立注册，互不依赖）。
        // 该通知一次插拔会连发多条，统一走 0.3s 合并防抖后再重建。
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

    /// - showSuppress: 是否显示"本次分心别再弹"按钮（AI 可能误判时给用户兜底，
    ///   通常仅在同一段 distract 内连续弹到第 3 次时由 SessionManager 传 true）
    func present(reminder: String, promise: String, showSuppress: Bool = false) {
        guard enabled else { return }
        // F2 修复：改用 dismissSilently() 而非 dismiss()。
        // 若旧遮罩仍显示时新一次 distract 触发 present()，SessionManager 已在调
        // present() 前把 onClosed 替换为新一轮的 cooldown 闭包。若此处调 dismiss()，
        // 则触发新闭包 → cooldown 从遮罩"被替换"瞬间起算而非用户点关闭时起算。
        // dismissSilently() 只关窗口、取消 autoCloseTask，不触发 onClosed。
        dismissSilently()

        // 留存 payload 供屏幕热插拔时按原样重建
        let payload = (reminder: reminder, promise: promise, showSuppress: showSuppress)
        lastPayload = payload

        // 每块屏各建一份全屏遮罩；取不到 displayID 的屏跳过并告警
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else {
                logger.warning("DistractOverlay: 跳过一块无法取得 displayID 的屏（\(screen.localizedName)）")
                continue
            }
            let panel = buildPanel(on: screen, payload: payload)
            windows[displayID] = panel
            panel.orderFrontRegardless()
        }

        // 一块屏都没盖上（无屏 / 全部取不到 displayID）→ 本次提醒生命周期即刻结束。
        // R1 修复：onClosed 语义统一为"本次提醒生命周期结束（无论真显示了还是没能显示）"。
        // SessionManager 调 present 前已把 cooldown 推到 distantFuture，全靠 onClosed 恢复
        // 计时；零屏路径若不 fire，该段 distract 提醒会被永久静默（直到 level 离开 distracted）
        guard !windows.isEmpty else {
            endLifecycleForZeroScreens()
            return
        }

        // 全局只有一个 30s 自动关任务，到点关全部屏
        autoCloseTask?.cancel()
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { self?.dismiss() }
            }
        }
    }

    /// 在指定屏上建全屏遮罩 panel（配置与单屏版逐项一致，仅 screen 参数化）。
    /// 闭包两屏共享同一份逻辑：任一屏 onDismiss/onSuppress → dismiss() 全关。
    private func buildPanel(
        on screen: NSScreen,
        payload: (reminder: String, promise: String, showSuppress: Bool)
    ) -> NSWindow {
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
                reminder: payload.reminder,
                promise: payload.promise,
                showSuppress: payload.showSuppress,
                onDismiss: { [weak self] in self?.dismiss() },
                onSuppress: { [weak self] in
                    guard let self else { return }
                    self.onSuppress?()
                    self.dismiss()
                }
            )
        )
        host.view.frame = NSRect(origin: .zero, size: screen.frame.size)
        host.view.autoresizingMask = [.width, .height]
        w.contentViewController = host
        w.setFrame(screen.frame, display: true)
        return w
    }

    // MARK: - 屏幕热插拔

    /// 屏幕参数变化通知入口——0.3s 合并防抖：一次插拔 / 改分辨率会连发多条通知，
    /// 只重建最后一次（任务可取消，重建前 cancel 上一个）。
    private func handleScreenParametersChanged() {
        screenChangeDebounceTask?.cancel()
        screenChangeDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.rebuildPanelsForScreenChange()
        }
    }

    /// 热插拔 / 分辨率 / 排列变化后按 lastPayload 全重建全部屏的遮罩。
    /// 全重建而非 diff：分辨率 / 排列变化时旧 frame 已失效。
    /// autoCloseTask 不动——30s 自动关仍从最初弹窗时刻起算，总时长不变。
    /// 连续触发 N 次结果一致（幂等）；镜像屏（NSScreen.screens 含镜像对）会在同一
    /// 物理输出上重叠显示相同内容，无害不处理。
    private func rebuildPanelsForScreenChange() {
        // 遮罩关着（windows 为空）或无 payload 时通知空转，零成本
        guard !windows.isEmpty, let payload = lastPayload else { return }

        // 只关旧窗——绝不走 dismiss() / dismissSilently()：
        // 两者都会取消 autoCloseTask / 清空 lastPayload / 可能 fire onClosed，
        // 热插拔重建必须保持"一次分心一次遮罩"的对外语义不变
        for (_, w) in windows {
            w.orderOut(nil)
            w.contentViewController = nil
        }
        windows.removeAll()

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else {
                logger.warning("DistractOverlay: 热插拔重建时跳过一块无法取得 displayID 的屏（\(screen.localizedName)）")
                continue
            }
            let panel = buildPanel(on: screen, payload: payload)
            windows[displayID] = panel
            panel.orderFrontRegardless()
        }

        // 与 present() 同语义（R1）：热插拔后一块屏都盖不上 → 本次提醒生命周期结束，
        // 清状态并 fire 一次 onClosed，恢复 SessionManager 的 cooldown 计时
        if windows.isEmpty {
            endLifecycleForZeroScreens()
        }
    }

    func dismiss() {
        let wasShown = !windows.isEmpty
        autoCloseTask?.cancel()
        autoCloseTask = nil
        for (_, w) in windows {
            w.orderOut(nil)
            w.contentViewController = nil
        }
        // 硬要求：先清空字典和 lastPayload，再 fire onClosed 恰好一次。
        // 双屏时任一屏按钮回调都会进 dismiss()；若先 fire 再清，
        // onClosed 闭包（或第二屏按钮的后续回调）重入 dismiss 时会看到
        // 非空字典再 fire 一次——double-fire 会打乱 FocusSessionManager 的 cooldown 语义
        windows.removeAll()
        lastPayload = nil
        if wasShown { onClosed?() }
    }

    /// F2 修复：静默关闭遮罩，不触发 onClosed 回调。
    /// present() 内部调用此方法替代 dismiss()，避免弹出新遮罩时
    /// 旧遮罩的 dismiss 触发已更新的 onClosed（新 session 的 cooldown 闭包），
    /// 导致 cooldown 从"遮罩被替换瞬间"起算而非用户真正点关闭时起算。
    /// autoCloseTask 仍被取消，确保旧的 30s 自动关定时器不残留。
    func dismissSilently() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        for (_, w) in windows {
            w.orderOut(nil)
            w.contentViewController = nil
        }
        windows.removeAll()
        lastPayload = nil
        // 不调 onClosed，由 present() 调用方自行管理 cooldown 计时
    }

    /// R1：零屏收尾——"应当弹出/维持但一块屏都没盖上"时统一走这里
    /// （present 空字典兜底、热插拔 rebuild 后零屏，共两处调用点）。
    /// onClosed 语义 = 本次提醒生命周期结束（无论真显示了还是没能显示）：
    /// SessionManager 靠它把 cooldown 从 distantFuture 拉回正常计时，
    /// 不 fire 的话该段 distract 提醒会被永久静默（直到 level 离开 distracted）。
    /// 顺序硬要求与 dismiss() 相同：先清状态（窗口 / payload / 自动关任务）再 fire，
    /// 每个生命周期恰好一次（fire 后 lastPayload 为 nil，rebuild 守卫不会重入）。
    /// NSScreen 不可 mock，零屏路径无法直接驱动——此方法是零屏语义的唯一可测入口。
    func endLifecycleForZeroScreens() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        for (_, w) in windows {
            w.orderOut(nil)
            w.contentViewController = nil
        }
        windows.removeAll()
        lastPayload = nil
        onClosed?()
    }
}

private struct DistractOverlayView: View {
    let reminder: String
    let promise: String
    let showSuppress: Bool
    let onDismiss: () -> Void
    let onSuppress: () -> Void

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

                // 拆三元：原写法 SwiftUI 推断成 Text(String)，"似乎偏离了承诺..." 不本地化
                Group {
                    if reminder.isEmpty {
                        Text("似乎偏离了承诺。回到正事？")
                    } else {
                        Text(reminder)
                    }
                }
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

                // 第 3 次起显示：AI 可能误判，本次分心区间内不再打扰
                if showSuppress {
                    Button {
                        onSuppress()
                    } label: {
                        Text("AI 可能误判 · 本次分心不再提醒")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .overlay(
                                Capsule().stroke(.white.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Text(showSuppress
                     ? "持续提醒已 3 次。可点上方按钮静默直到状态恢复 · 30 秒后自动消失"
                     : "点击「我回来了」返回 · 30 秒后自动消失")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
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
