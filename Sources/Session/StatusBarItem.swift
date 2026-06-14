import AppKit

/// 菜单栏常驻图标。点击 → 唤起 PromisePanel。
///
/// 行为：
/// - 左键单击：弹出 PromisePanel（如已在跑 session，仅做"激活前置"用途）
/// - 右键 / 长按：弹出菜单（开始专注 / 显示主窗口 / 退出）
@MainActor
final class StatusBarItem {
    static let shared = StatusBarItem()

    private var item: NSStatusItem?
    private weak var sessionMgr: FocusSessionManager?

    private init() {}

    /// App 启动一次，安装到系统菜单栏右侧。
    func install(sessionMgr: FocusSessionManager) {
        guard item == nil else { return }
        self.sessionMgr = sessionMgr

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let img = NSImage(named: "MenubarIcon")
            img?.isTemplate = true  // 系统自动反色：浅模式黑、深模式白
            button.image = img
            button.toolTip = L("Vigil · 点击开始一次专注")
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.item = item
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            startPromise()
        }
    }

    private func startPromise() {
        guard let mgr = sessionMgr else { return }
        PromisePanel.toggle(sessionMgr: mgr)
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let focusWindows = NSApp.windows.filter { $0.title == "Vigil" }
        guard let target = focusWindows.first else { return }
        // hideOnClose 让旧窗口残留 + SwiftUI 仍会按需创建新实例，可能累积多个；
        // 只保留第一个为主窗口，其余统一 orderOut 防止"一点击冒 5 个窗口"
        for w in focusWindows where w !== target {
            w.orderOut(nil)
        }
        target.makeKeyAndOrderFront(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        // 每次弹菜单时现读 L()，保证用户切语言后立即生效
        menu.addItem(withTitle: L("开始专注…"), action: #selector(menuStart), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: L("显示主窗口"), action: #selector(menuShowMain), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        // keyEquivalent: "," 默认带 ⌘ 修饰符，菜单里展示 ⌘, 提示。
        // SwiftUI Settings scene 本身就响应系统级 ⌘,，提示和实际可用快捷键一致。
        menu.addItem(withTitle: L("设置…"), action: #selector(menuOpenSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("退出 Vigil"), action: #selector(menuQuit), keyEquivalent: "q")
            .target = self
        item?.menu = menu
        item?.button?.performClick(nil)
        item?.menu = nil  // 清掉，避免下次左键也弹菜单
    }

    @objc private func menuStart() { startPromise() }
    @objc private func menuShowMain() { showMainWindow() }
    @objc private func menuOpenSettings() {
        // 菜单栏触发时其他 App 通常在前台，必须先 activate 才能让 Settings window 真正
        // 拿到键盘焦点。SwiftUI 14+ 的 Settings scene 响应 showSettingsWindow: selector。
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
