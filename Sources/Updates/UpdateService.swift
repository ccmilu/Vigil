import Foundation
import SwiftUI

/// 自动更新协调器（singleton）。
///
/// 职责：
/// - 启动时延迟 5s 跑一次检查（让冷启动主流程优先）
/// - 注册 24h Timer 周期性检查
/// - 暴露 manualCheck() 供 Settings 里"立即检查"按钮调用
/// - 检查到新版 → `presentingUpdate` 触发主窗口的 sheet
/// - 持有 UpdateDownloader 实例，UI 直接观察其 state
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    /// 后台周期性检查间隔（24h）
    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// 启动后多少秒首次检查
    static let startupDelay: TimeInterval = 5

    /// 当前检查状态（Settings 里展示）
    @Published private(set) var state: UpdateCheckState = .idle
    /// 一旦有新版本，把它放进来就会触发主窗口 sheet
    @Published var presentingUpdate: ReleaseInfo?

    /// 暴露给 UI 的下载器（同一实例贯穿整个 App 生命周期）
    let downloader = UpdateDownloader()

    private let checker: UpdateChecker
    private let settings: AppSettings
    private var timer: Timer?
    private var startupTask: Task<Void, Never>?

    private init(checker: UpdateChecker = UpdateChecker(), settings: AppSettings = .shared) {
        self.checker = checker
        self.settings = settings
    }

    /// 由 FocusApp 启动调一次。重复调用安全（先清掉旧 task / timer）。
    func start() {
        startupTask?.cancel()
        // Task inherits @MainActor from enclosing context
        startupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.startupDelay * 1_000_000_000))
            guard let self else { return }
            if self.settings.autoCheckUpdates {
                await self.runCheck(automatic: true)
            }
        }
        installTimer()
    }

    /// 用户在 Settings 点"立即检查更新"。
    /// 不受 autoCheckUpdates 开关影响——用户主动行为永远响应。
    func manualCheck() {
        Task { @MainActor in
            await self.runCheck(automatic: false)
        }
    }

    /// 用户在 sheet 上点"稍后" / 关闭。
    func dismissUpdateSheet() {
        presentingUpdate = nil
    }

    func currentVersion() -> SemanticVersion {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let v = SemanticVersion(s) else {
            return SemanticVersion("0.0.0")!
        }
        return v
    }

    /// "上次检查"时间，给 Settings 展示用。
    var lastCheckedAt: Date? {
        if let d = state.lastCheckedAt { return d }
        let ts = settings.lastUpdateCheckTimestamp
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    private func installTimer() {
        timer?.invalidate()
        // Timer 永远在跑；闭包内根据 settings.autoCheckUpdates 决定是否真发请求。
        // 这样关掉再开不需要重启 App，下一次 tick 自动恢复。
        let interval = Self.checkInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.settings.autoCheckUpdates {
                    await self.runCheck(automatic: true)
                }
            }
        }
    }

    private func runCheck(automatic: Bool) async {
        // 节流：自动检查在 60s 内不重复（手动检查跳过这个限制）
        if automatic {
            let last = settings.lastUpdateCheckTimestamp
            if last > 0 {
                let elapsed = Date().timeIntervalSince1970 - last
                if elapsed < UpdateChecker.minRequestInterval {
                    return
                }
            }
        }

        state = .checking
        do {
            let release = try await checker.fetchLatestRelease()
            let now = Date()
            settings.lastUpdateCheckTimestamp = now.timeIntervalSince1970
            if release.version > currentVersion() {
                state = .available(release)
                // 已经在弹窗时不重复触发（避免用户关掉再被 24h 检查重新打开）
                if presentingUpdate == nil {
                    presentingUpdate = release
                }
            } else {
                state = .upToDate(now)
            }
        } catch {
            state = .error(error.localizedDescription, Date())
        }
    }
}
