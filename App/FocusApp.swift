import SwiftUI
import SwiftData
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⇧⌘⌥Space。⌘⌥Space 默认被 Spotlight 占用。
    static let startPromise = Self(
        "startPromise",
        default: .init(.space, modifiers: [.command, .option, .shift])
    )
}

@main
struct FocusApp: App {
    private let modelContainer = AppContainer.shared

    @StateObject private var providerStore = ProviderStore()
    @StateObject private var sessionMgr: FocusSessionManager

    init() {
        // 临时引用，避免 @StateObject 闭包捕获错乱
        let providers = ProviderStore()
        let mgr = FocusSessionManager(
            modelContainer: AppContainer.shared,
            serviceFactory: { @MainActor in
                providers.selected?.makeService() ?? OpenAICompatibleService()
            }
        )
        _providerStore = StateObject(wrappedValue: providers)
        _sessionMgr = StateObject(wrappedValue: mgr)
    }

    var body: some Scene {
        WindowGroup("Focus") {
            ContentView()
                .environmentObject(sessionMgr)
                .environmentObject(providerStore)
                .frame(minWidth: 560, minHeight: 420)
                .task {
                    await Notifier.requestAuthorization()
                    KeyboardShortcuts.onKeyUp(for: .startPromise) { [sessionMgr] in
                        Task { @MainActor in
                            PromisePanel.show(sessionMgr: sessionMgr)
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
                .frame(width: 480, height: 320)
        }
    }
}
