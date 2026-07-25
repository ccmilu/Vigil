import AppKit
import SwiftUI

// MARK: - 每屏岛控制器

/// 每块显示器一座刘海岛——本类持有一屏的 panel / 鼠标监听 / 轮询 Timer，
/// 全部从 NotchTimer 原样搬运并逐屏参数化（NSScreen.main → self.screen）。
///
/// 共享业务状态（remaining / level / forceExpandUntil / timeline …）仍由
/// `state`（NotchTimer singleton）持有——distract / idle / wandering 的
/// forceExpandUntil 是全局语义，所有岛同时展开；
/// `hovering` 是本岛私有状态——hover 展开只展开被 hover 的这一座岛。
///
/// 生命周期：show() / teardown() 必须配对。teardown 漏任何一步
/// （orderOut / 摘两个 monitor / invalidate Timer / 释放 window）
/// 都会随热插拔累积泄漏。
@MainActor
final class NotchIslandController: ObservableObject {
    /// 本岛所在屏幕
    let screen: NSScreen
    /// 本屏的显示器 ID（取自 screen.displayID；理论取不到时回退主屏 ID，仅作信息字段）
    let displayID: CGDirectDisplayID
    /// 共享业务状态（NotchTimer singleton，由其持有 self，绝不会先释放）
    unowned let state: NotchTimer

    /// 鼠标是否在这座岛上 hover——PassthroughHostingView 也算 hit rect 用
    @Published var hovering: Bool = false

    private var window: NSPanel?
    private var mouseLocalMonitor: Any?
    private var mouseGlobalMonitor: Any?
    private var hoverPollTimer: Timer?

    init(screen: NSScreen, state: NotchTimer) {
        self.screen = screen
        self.displayID = screen.displayID ?? CGMainDisplayID()
        self.state = state
    }

    /// 预览 / 测试便捷构造：不显式给屏时用主屏（headless 环境最终回退一个空 NSScreen，
    /// 仅保证可构造——预览与测试不会真的 show()）
    convenience init(state: NotchTimer, screen: NSScreen? = nil) {
        self.init(screen: screen ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen(), state: state)
    }

    // MARK: - 生命周期（配对！）

    func show() {
        if window == nil { createWindow() }
        window?.orderFrontRegardless()
    }

    /// 与 show() 配对：关窗 + 摘两个 monitor + invalidate Timer + 释放 window，一个都不能漏
    func teardown() {
        stopMouseTracking()
        hovering = false
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - 岛几何（按本屏参数）

    /// 本屏的折叠 / 展开几何尺寸（有 / 无刘海走不同公式，集中在 IslandGeometry.compute）
    var islandGeometry: IslandGeometry {
        IslandGeometry.compute(for: screen)
    }

    /// 当前岛实际矩形（panel-local 坐标），矩形数学与 NotchTimer 兼容壳共用同一纯函数。
    /// - panelSize: NSHostingView.bounds.size
    /// - isFlipped: NSHostingView.isFlipped — true 时 y=0 是顶，false 时 y=0 是底
    func currentIslandRect(in panelSize: NSSize, isFlipped: Bool = true) -> NSRect {
        let isExpanded = hovering || (state.forceExpandUntil.map { $0 > Date() } ?? false)
        return islandGeometry.islandRect(isExpanded: isExpanded, in: panelSize, isFlipped: isFlipped)
    }

    // MARK: - 鼠标追踪（只作用本岛 panel）

    private func stopMouseTracking() {
        if let m = mouseLocalMonitor { NSEvent.removeMonitor(m); mouseLocalMonitor = nil }
        if let m = mouseGlobalMonitor { NSEvent.removeMonitor(m); mouseGlobalMonitor = nil }
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
    }

    /// 用全局鼠标位置驱动 panel.ignoresMouseEvents：
    /// - 鼠标进入岛实际矩形 → panel 接收事件 + hovering=true（SwiftUI 展开本岛）
    /// - 鼠标离开 → panel.ignoresMouseEvents=true 全穿透，下方应用能点击
    /// - forceExpandUntil 期间永远保持接收（不让用户错过软提醒）
    private func startMouseTracking() {
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
            // Timer 加到 RunLoop.main 的 .common mode，闭包必然在主线程 fire——
            // 用 assumeIsolated 桥接 Swift 6 严格并发（闭包类型是 @Sendable nonisolated），
            // 不引入 Task 跳转避免改变 0.05s 轮询的时序语义
            MainActor.assumeIsolated {
                self?.refreshHoverState()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        hoverPollTimer = t
    }

    /// 逐行对照原 NotchTimer 实现搬运——只读写本岛 panel / 本岛 hovering，
    /// forceExpandUntil 仍读全局 state（所有岛同时展开的语义来源）。
    /// 跨屏坐标安全性：NSEvent.mouseLocation 与 NSWindow.frame 同在全局屏幕坐标系
    /// （主屏原点 (0,0)，副屏按排列延伸），panelFrame.origin + 本岛 local 偏移即得
    /// 全局岛矩形，副屏 origin 非 (0,0) 时数学天然成立，无需额外换算。
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
        let forceExpanded = (state.forceExpandUntil ?? .distantPast) > Date()

        let shouldReceive = inside || forceExpanded
        if panel.ignoresMouseEvents != !shouldReceive {
            panel.ignoresMouseEvents = !shouldReceive
        }
        if hovering != inside {
            hovering = inside
        }
    }

    // MARK: - 建窗

    private func createWindow() {
        let screen = self.screen
        // panel 尺寸用展开态上限做窗口大小；岛在内部居中缩放
        // 从本屏几何读展开态宽度，与 currentIslandRect / NotchView 保持一致
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
        // 折叠态岛只占很小一块但 panel 矩形全拦截下方点击。
        // PassthroughHostingView 让 SwiftUI 子视图没命中时返回 nil → 事件穿透。
        let host = PassthroughHostingView(rootView: NotchView(state: state, controller: self))
        host.controller = self
        host.frame = NSRect(origin: .zero, size: NSSize(width: panelW, height: panelH))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        window = panel
        startMouseTracking()
    }
}

// MARK: - Panel / HostingView（从 NotchTimer.swift 搬入，去 private 供跨文件引用）

final class FloatingNotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// hitTest 行为修正：直接拿 controller 算出的当前岛矩形过滤鼠标命中。
/// 岛之外的整块 panel 区域返回 nil，事件穿透到下方应用。
/// SwiftUI 默认会让 panel 整个 frame 接收 hit-test（即使透明），所以必须在
/// NSView 层主动拦截，不能只靠 SwiftUI 自己的 hit-test 推断。
/// hitTest 兜底：panel.ignoresMouseEvents 已经控制了"事件是否进入 panel"的整体行为，
/// 这里再加一层 view-local 过滤——避免极端情况下（global monitor 来不及更新）
/// 点击穿过岛旁边的透明区域命中 self。
/// controller 为 nil 时（不应发生）退化 super.hitTest，不再硬引用 NotchTimer.shared。
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    weak var controller: NotchIslandController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let islandRect = controller.currentIslandRect(in: bounds.size, isFlipped: isFlipped)
        guard islandRect.contains(local) else { return nil }
        return super.hitTest(point)
    }
}
