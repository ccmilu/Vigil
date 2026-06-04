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
            button.toolTip = "Focus · 点击开始一次专注"
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
        for w in NSApp.windows where w.title == "Focus" {
            w.makeKeyAndOrderFront(nil)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "开始专注…", action: #selector(menuStart), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "显示主窗口", action: #selector(menuShowMain), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Focus", action: #selector(menuQuit), keyEquivalent: "q")
            .target = self
        item?.menu = menu
        item?.button?.performClick(nil)
        item?.menu = nil  // 清掉，避免下次左键也弹菜单
    }

    @objc private func menuStart() { startPromise() }
    @objc private func menuShowMain() { showMainWindow() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
