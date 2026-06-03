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
    @StateObject private var appSettings = AppSettings()
    @StateObject private var sessionMgr: FocusSessionManager

    init() {
        let providers = ProviderStore()
        let settings = AppSettings()
        let mgr = FocusSessionManager(
            modelContainer: AppContainer.shared,
            settings: settings,
            serviceFactory: { @MainActor sink in
                providers.selected?.makeService(debugSink: sink)
                    ?? OpenAICompatibleService(debugSink: sink)
            }
        )
        _providerStore = StateObject(wrappedValue: providers)
        _appSettings = StateObject(wrappedValue: settings)
        _sessionMgr = StateObject(wrappedValue: mgr)
    }

    var body: some Scene {
        WindowGroup("Focus") {
            ContentView()
                .environmentObject(sessionMgr)
                .environmentObject(providerStore)
                .environmentObject(appSettings)
                .frame(minWidth: 560, minHeight: 420)
                .task {
                    await Notifier.setUp()
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
                .environmentObject(appSettings)
                .environmentObject(providerStore)
        }
    }
}
