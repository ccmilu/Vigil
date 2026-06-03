import SwiftUI
import KeyboardShortcuts

// 注册全局快捷键名（其它地方通过 .startPromise 引用即可）
extension KeyboardShortcuts.Name {
    static let startPromise = Self("startPromise", default: .init(.space, modifiers: [.command, .option]))
}

@main
struct FocusApp: App {
    @StateObject private var sessionVM = SessionViewModel()

    var body: some Scene {
        WindowGroup("Focus") {
            ContentView()
                .environmentObject(sessionVM)
                .frame(minWidth: 520, minHeight: 360)
                .task {
                    // 启动时把 ⌘⌥Space 绑定到弹窗
                    KeyboardShortcuts.onKeyUp(for: .startPromise) { [sessionVM] in
                        Task { @MainActor in
                            PromisePanel.show(sessionVM: sessionVM)
                        }
                    }
                }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .frame(width: 480, height: 320)
        }
    }
}
