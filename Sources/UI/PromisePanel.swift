import AppKit
import SwiftData
import SwiftUI

enum PromisePanel {
    static let savedFrameKey = "PromisePanel.frame"

    @MainActor
    static func show(sessionMgr: FocusSessionManager) {
        // 已有 session 在跑（preparing / running / resting / analyzing）就别开 panel，
        // 改为激活主窗口让用户看到当前 phase 视图——同一时间只允许一个专注
        guard sessionMgr.phase.allowsNewSession else {
            activateMainWindow()
            return
        }
        // activate 之前快照两类状态，panel 关闭时要回滚：
        // 1) 原本隐藏的主窗口（hideOnClose 用 orderOut → isVisible=false）——
        //    activate 可能让 SwiftUI 把它们拉回前台，关闭时要重新 orderOut。
        // 2) 原本在前台的其他 App——关闭 panel 后让它重新 activate，
        //    实现 Spotlight 那种"用完即走"、不抢前台的体感。
        let hiddenMainsBeforeActivate = NSApp.windows.filter {
            $0.title == "Focus" && !$0.isVisible
        }
        let prevFrontApp = NSWorkspace.shared.frontmostApplication

        // 必须先 activate App，否则 makeKey() 在 App 非 active 时静默失效——
        // 快捷键 / 菜单栏触发时其他 App 在前台，panel 会浮出但拿不到键盘焦点。
        NSApp.activate(ignoringOtherApps: true)
        if let existing = PromisePanelWindow.shared {
            existing.orderFrontRegardless()
            existing.makeKey()
            return
        }
        let win = PromisePanelWindow(sessionMgr: sessionMgr)
        win.hiddenMainsBeforeActivate = hiddenMainsBeforeActivate
        // prev app 是 Focus 自己（如从主窗口按钮触发）就别记录，避免关 panel 后
        // 自己再 activate 自己造成主窗口闪烁
        if let prev = prevFrontApp,
           prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            win.prevFrontAppBeforeActivate = prev
        }
        PromisePanelWindow.shared = win
        // 手动从 UserDefaults 还原 frame；首次/无记录则居中。
        // 不用 setFrameAutosaveName，避免 documentWindow 动画期间 frame
        // 被动改写时被自动保存导致位置每次累积漂移。
        if let frameString = UserDefaults.standard.string(forKey: savedFrameKey) {
            let rect = NSRectFromString(frameString)
            if rect.width > 0 && rect.height > 0 {
                win.setFrame(rect, display: false)
            } else {
                win.center()
            }
        } else {
            win.center()
        }
        win.orderFrontRegardless()
        win.makeKey()
    }

    /// 快捷键专用：已打开则关闭，未打开则打开。
    /// 动画进行中（isClosing）时忽略，避免重叠创建闪烁。
    @MainActor
    static func toggle(sessionMgr: FocusSessionManager) {
        if let existing = PromisePanelWindow.shared {
            if !existing.isClosing {
                existing.close()
            }
            // 否则正在 fade-out 动画中，忽略本次按键
        } else {
            // 进行中也别开 panel；show() 内部会再走一次 guard，但快捷键路径
            // 在这里直接拦截能避免动画闪烁
            guard sessionMgr.phase.allowsNewSession else {
                activateMainWindow()
                return
            }
            show(sessionMgr: sessionMgr)
        }
    }

    /// session 正在跑时，把主窗口拉到前面让用户看到当前 phase 视图
    @MainActor
    private static func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.title == "Focus" {
            w.makeKeyAndOrderFront(nil)
            return
        }
    }
}

final class PromisePanelWindow: NSPanel {
    nonisolated(unsafe) static var shared: PromisePanelWindow?

    /// fade-out 动画期间的标志，防止 toggle 在动画中重入
    var isClosing = false

    /// show() 时记录的"本来是隐藏的主窗口"。close 后要把它们 orderOut，
    /// 避免 NSApp.activate 把 hideOnClose 隐藏的主窗口意外拉回前台。
    var hiddenMainsBeforeActivate: [NSWindow] = []

    /// show() 时记录的"原本在前台的其他 App"。close 后让它重新 activate，
    /// 实现 Spotlight 那种用完即走、不抢前台的体感。
    /// 必须强引用——NSRunningApplication 没人持有会立刻释放，weak 会变 nil。
    var prevFrontAppBeforeActivate: NSRunningApplication?

    init(sessionMgr: FocusSessionManager) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "这次专注做什么？"
        isFloatingPanel = true
        level = .floating
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // 玻璃化：让 NSPanel 透明，由 SwiftUI 内容自己提供 material 背景
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        // 标准 fade-in/out 动画，与主窗口 / Settings 一致
        animationBehavior = .documentWindow

        // 注入 modelContainer，使 PromisePanelContent 内的 @Query 能访问 SwiftData 上下文。
        // NSPanel 不在 WindowGroup 内，需手动注入；使用 AppContainer.shared 单例。
        contentViewController = NSHostingController(
            rootView: PromisePanelContent(sessionMgr: sessionMgr, dismiss: { [weak self] in
                self?.close()
            })
            .background(.thinMaterial)
            .modelContainer(AppContainer.shared)
        )
    }
    override func close() {
        guard !isClosing else { return }
        isClosing = true
        // 在动画启动之前保存当前 frame；动画期间 frame 可能被系统改写，
        // 此刻保存的是用户真实拖到的位置。
        UserDefaults.standard.set(
            NSStringFromRect(self.frame),
            forKey: PromisePanel.savedFrameKey
        )

        // 立即回滚 activate 的副作用——必须在 super.close() 触发 fade-out 之前，
        // 否则用户会看到主窗口先浮起来一下再回去。
        for w in hiddenMainsBeforeActivate where w.isVisible {
            w.orderOut(nil)
        }
        hiddenMainsBeforeActivate.removeAll()
        if let prev = prevFrontAppBeforeActivate, !prev.isTerminated {
            prev.activate()
        }
        prevFrontAppBeforeActivate = nil

        super.close()
        // documentWindow 动画约 200ms，等动画结束才清 shared 和重置标志，
        // 避免动画期间 toggle 再次访问 shared = nil 造成重叠新建
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            if Self.shared === self {
                Self.shared = nil
            }
            self.isClosing = false
        }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct PromisePanelContent: View {
    let sessionMgr: FocusSessionManager
    let dismiss: () -> Void

    /// 用 @AppStorage 持久化最近一次输入，下次打开面板自动预填
    @AppStorage("promise.lastInput") private var promise: String = ""
    @AppStorage("promise.lastDurationMin") private var durationMin: Int = 25
    @State private var isStarting = false
    @State private var aiSuggestion: String? = nil   // 非 nil 说明 promise 不够具体
    @State private var aiUnreachable: String? = nil  // 非 nil 说明 AI 服务连不上
    @State private var hasAskedAI = false
    @FocusState private var focused: Bool

    /// 从 SwiftData 读取用户时长预设，按 slot 升序排列。
    /// 需要 modelContainer 注入到视图树（由 PromisePanelWindow 在 NSHostingController 注入）。
    /// TODO: 未来在 Settings 加增删改 UI，让用户自定义预设列表（最多 9 个）。
    @Query(sort: \PlayTimer.slot) private var timers: [PlayTimer]

    /// 当前时长预设（分钟列表）。
    /// 若 PlayTimer 表非空则从数据库读取（取前 9 个去重），否则回退到默认 5 项。
    /// TODO: 当预设超过 5 个时，考虑支持 9 个全局快捷键与 PlayTimer 绑定。
    private var presetMinutes: [Int] {
        guard !timers.isEmpty else {
            return Migrations.defaultPresetMinutes
        }
        // 将 seconds 转为分钟（整数），去重后最多取 9 个
        var seen = Set<Int>()
        var result: [Int] = []
        for t in timers.prefix(9) {
            let m = t.seconds / 60
            if seen.insert(m).inserted {
                result.append(m)
            }
        }
        return result.isEmpty ? Migrations.defaultPresetMinutes : result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("我这次要专注于…")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextField("例：完成季度报告初稿", text: $promise, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(2...4)
                .focused($focused)

            if let suggestion = aiSuggestion {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                    Text(suggestion)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 6))
            }

            if let unreachable = aiUnreachable {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(.red)
                        Text("无法连接 AI 服务")
                            .font(.callout.weight(.medium))
                    }
                    Text(unreachable)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(10)
                .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Text("时长")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(presetMinutes, id: \.self) { m in
                    Button("\(m)") { durationMin = m }
                        .glassButtonStyle(prominent: durationMin == m)
                        .controlSize(.small)
                }
                Text("分钟")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                if aiSuggestion == nil && aiUnreachable == nil {
                    Button(isStarting ? "校验中…" : "开始 \(durationMin) 分钟") {
                        Task { await onStartTapped() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .glassButtonStyle(prominent: true)
                    .disabled(promise.trimmingCharacters(in: .whitespaces).isEmpty || isStarting)
                } else if aiUnreachable != nil {
                    Button("重试") { Task { await onStartTapped() } }
                    Button("仍然开始（离线）") { Task { await actuallyStart() } }
                        .glassButtonStyle(prominent: true)
                } else {
                    Button("仍然开始") { Task { await actuallyStart() } }
                        .glassButtonStyle(prominent: true)
                        .disabled(isStarting)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            // NSHostingController 嵌入 NSPanel 时 @FocusState 设置过早会失效，延迟 50ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focused = true
            }
        }
        .onChange(of: promise) { _, _ in
            // 用户改了 promise 后清除上次的反问 / 错误
            aiSuggestion = nil
            aiUnreachable = nil
            hasAskedAI = false
        }
    }

    /// 第一次点 Start：先调 validatePromise 校验 + 探活
    private func onStartTapped() async {
        let trimmed = promise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isStarting = true
        defer { isStarting = false }
        aiSuggestion = nil
        aiUnreachable = nil

        switch await sessionMgr.validatePromise(trimmed) {
        case .clear:
            await actuallyStart()
        case .needsClarification(let s):
            aiSuggestion = s
            hasAskedAI = true
        case .serviceUnreachable(let msg):
            aiUnreachable = msg
        }
    }

    /// 用户改完 promise 后点"仍然开始"，跳过二次校验
    private func actuallyStart() async {
        let trimmed = promise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isStarting = true
        defer { isStarting = false }
        _ = await sessionMgr.start(promise: trimmed, durationSeconds: durationMin * 60)
        dismiss()
    }
}
