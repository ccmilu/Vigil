import Foundation
import SwiftUI

/// 用户可选的 App 语言。
///
/// - `system`：跟随系统首选语言（macOS Preferences → General → Language）
/// - `zhHans`：强制简体中文
/// - `en`：强制英文
///
/// 目前只支持中英两种，未来扩展时只需加 case + 在 xcstrings 里补对应 locale 的翻译即可。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    /// 在 Settings 里展示的人类可读名字。
    /// 注意这里**不本地化**——三种语言名字都用各自语言展示，让用户在任何语言下都能识别。
    var displayName: String {
        switch self {
        case .system: return "System / 跟随系统"
        case .zhHans: return "简体中文"
        case .en:     return "English"
        }
    }

    /// 当 self == .system 时，结合当前系统首选语言推导出"实际生效"的语言。
    /// 否则原样返回。所有"需要明确语言"的下游（prompt 注入 / Bundle 选择）都走这个。
    var effective: AppLanguage {
        switch self {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? .zhHans : .en
        default:
            return self
        }
    }

    /// 注入到 SwiftUI 的 `\.locale` environment 值。
    /// system 也返回明确 locale（不返回 nil）——确保 SwiftUI Text 走 LocalizedStringKey 时
    /// 命中正确的 lproj，而不是回退到 main bundle 默认（development region = zh-Hans）。
    var locale: Locale {
        Locale(identifier: effective.rawValue)
    }

    /// 对应到 main bundle 内的 lproj 子 Bundle。找不到时回落 main。
    var bundle: Bundle {
        let target = effective.rawValue
        if let path = Bundle.main.path(forResource: target, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return .main
    }

    /// 注入到 AI prompt 里的"返回语言"自然语言名。
    /// 用 AI 能识别的标准说法，避免厂商兼容性差异（部分小模型对"简体中文" vs
    /// "中文（简体）"敏感）。
    var promptLanguageName: String {
        switch effective {
        case .zhHans: return "Simplified Chinese (简体中文)"
        case .en:     return "English"
        case .system: return effective.promptLanguageName  // effective 不可能再是 .system
        }
    }
}

/// 切换 App 语言的全局协调中心。
///
/// 设计要点：
/// - 单例，跟 `AppSettings.shared` 平级，保证所有 SwiftUI 树和 AppKit 部分读到同一份语言
/// - `@Published language` 让 SwiftUI 视图自动跟随
/// - 写入 (`setLanguage`) 在 @MainActor；nonisolated 入口（如 enum displayName 的 L() 调用）
///   读 `UserDefaults` 直接拿，不经过 actor，避免线程切换开销与死锁
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// 当前选择的语言。读写都跑主线程（@Published 默认行为）。
    /// nonisolated 入口请用 `LocalizationManager.effectiveLanguageFromDefaults()` 不要读这个。
    @Published private(set) var language: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: "app.language") ?? AppLanguage.system.rawValue
        self.language = AppLanguage(rawValue: raw) ?? .system
    }

    /// 写入新语言（持久化 + 通知 SwiftUI 重渲染 + AppKit 端下次构造拿新 bundle）。
    func setLanguage(_ new: AppLanguage) {
        guard new != language else { return }
        language = new
        UserDefaults.standard.set(new.rawValue, forKey: "app.language")
    }

    // MARK: - nonisolated 静态入口（给 enum displayName / Notifier / NSMenu 等没有 actor context 的代码用）

    /// 直接读 UserDefaults，不依赖单例实例状态。
    /// 任何线程都能安全调用。
    nonisolated static func effectiveLanguageFromDefaults() -> AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "app.language") ?? AppLanguage.system.rawValue
        return (AppLanguage(rawValue: raw) ?? .system).effective
    }

    /// AppKit 端使用的当前 Bundle，用于 `NSLocalizedString(...bundle:)`。
    nonisolated static var currentBundle: Bundle {
        effectiveLanguageFromDefaults().bundle
    }

    /// AI prompt 注入用的"返回语言名"。
    /// SessionManager / validatePromise 用这个拿用户当前语言注入到 prompt。
    nonisolated static var promptLanguageName: String {
        effectiveLanguageFromDefaults().promptLanguageName
    }
}

// MARK: - 全局便捷函数

/// AppKit 部分（NSMenu / NSAlert / Notifier 等不走 SwiftUI environment 的代码）
/// 用这个查 LocalizationManager 决定的当前 Bundle 的翻译。
///
/// SwiftUI 视图里**不要**用这个——直接用 `Text("中文 key")` 让 SwiftUI 通过
/// `.environment(\.locale)` 自动找翻译，比手写更整洁。
func L(_ key: String, comment: String = "") -> String {
    NSLocalizedString(
        key,
        bundle: LocalizationManager.currentBundle,
        value: key,
        comment: comment
    )
}

/// 带格式化参数的版本：`L("欢迎 %@", args: userName)`。
func L(_ key: String, args: CVarArg..., comment: String = "") -> String {
    let fmt = NSLocalizedString(
        key,
        bundle: LocalizationManager.currentBundle,
        value: key,
        comment: comment
    )
    return String(format: fmt, arguments: args)
}
