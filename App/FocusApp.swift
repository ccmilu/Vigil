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
    @StateObject private var localizer = LocalizationManager.shared

    /// 全局副作用只跑一次。SwiftUI App init 可能因为 environment 变化被多次调用；
    /// 主窗口关闭重开时 ContentView 的 .task 会重跑——快捷键 / Notifier / StatusBar 注册
    /// 都不能放在 .task 里，否则 KeyboardShortcuts 会累加回调互相抵消。
    private nonisolated(unsafe) static var didSetupGlobals = false

    init() {
        // 用 shared 单例，避免 @StateObject 在多次 init 中创建临时实例导致
        // serviceFactory 闭包捕获的 store 与 environment 暴露的 store 不一致
        let providers = ProviderStore.shared
        let settings = AppSettings.shared
        let mgr = FocusSessionManager(
            modelContainer: AppContainer.shared,
            settings: settings,
            serviceFactory: { @MainActor sink, lang in
                providers.selected?.makeService(debugSink: sink, responseLanguage: lang)
                    ?? OpenAICompatibleService(debugSink: sink, responseLanguage: lang)
            }
        )
        _providerStore = StateObject(wrappedValue: providers)
        _appSettings = StateObject(wrappedValue: settings)
        _sessionMgr = StateObject(wrappedValue: mgr)

        if !Self.didSetupGlobals {
            Self.didSetupGlobals = true
            Notifier.setUp()
            // 注意：StatusBar / 快捷键回调要 @MainActor 派发以访问 sessionMgr
            DispatchQueue.main.async {
                Migrations.runAll(container: AppContainer.shared)
                StatusBarItem.shared.install(sessionMgr: mgr)
            }
            KeyboardShortcuts.onKeyUp(for: .startPromise) {
                Task { @MainActor in
                    PromisePanel.toggle(sessionMgr: mgr)
                }
            }
        }
    }

    @AppStorage("onboarding.completed") private var onboardingDone = false

    var body: some Scene {
        WindowGroup("Vigil") {
            ZStack {
                ContentView()
                    .environmentObject(sessionMgr)
                    .environmentObject(providerStore)
                    .environmentObject(appSettings)
                    .environmentObject(localizer)
                    .frame(minWidth: 560, minHeight: 420)
                if !onboardingDone {
                    Color.black.opacity(0.001)  // 拦截背后交互
                        .ignoresSafeArea()
                    OnboardingView { onboardingDone = true }
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                        .transition(.opacity)
                }
            }
            .glassWindow(hideOnClose: true)
            // 注入用户选择的 locale 让 SwiftUI Text(LocalizedStringKey) 跟随翻译。
            // .system 时也注入明确 locale，避免回退到 development region 默认 (zh-Hans)
            .environment(\.locale, localizer.language.locale)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
                .environmentObject(appSettings)
                .environmentObject(providerStore)
                .environmentObject(localizer)
                .environment(\.locale, localizer.language.locale)
                .glassWindow()
        }
    }
}

extension View {
    /// 把承载 SwiftUI Scene 的窗口背景换成液态玻璃 material，
    /// 并让底层 NSWindow 透明，让 material 真正透出。
    ///
    /// macOS 15+ 用 containerBackground；macOS 14 用普通 background fallback。
    @ViewBuilder
    func glassWindow(hideOnClose: Bool = false) -> some View {
        if #available(macOS 15.0, *) {
            self
                .containerBackground(.thinMaterial, for: .window)
                .background(GlassWindowAccessor(transparentTitlebar: true, hideOnClose: hideOnClose))
        } else {
            self
                .background(.thinMaterial)
                .background(GlassWindowAccessor(transparentTitlebar: true, hideOnClose: hideOnClose))
        }
    }
}
