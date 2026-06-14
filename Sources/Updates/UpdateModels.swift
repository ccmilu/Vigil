import Foundation

/// 从 GitHub Releases API 解析出的版本信息，是 UpdateChecker 的产物。
struct ReleaseInfo: Equatable, Identifiable {
    let tagName: String              // 原始 tag，例如 "v0.1.3" 或 "0.1.3"
    let name: String                 // GitHub Release 标题
    let version: SemanticVersion     // 去掉 v 前缀后的语义化版本
    let body: String                 // Markdown 形式的更新说明
    let htmlURL: URL                 // 浏览器可打开的 release 页
    let dmgURL: URL?                 // .dmg 资源直链；没找到时为 nil（走打开网页 fallback）
    let publishedAt: Date?           // GitHub 发布时间，仅展示用

    var id: String { tagName }
}

/// 语义化版本号（major.minor.patch[.build]），用于比较"哪个更新"。
///
/// 解析规则：
/// - 允许前缀 "v" / "V"
/// - 忽略 build metadata（"+xxx"）与 pre-release（"-xxx"）后缀
/// - 长度可以不同，缺失分量按 0 补齐再比较（"1.0" 与 "1.0.0" 视为相等）
struct SemanticVersion: Comparable, Equatable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, first == "v" || first == "V" {
            s.removeFirst()
        }
        if let i = s.firstIndex(where: { $0 == "+" || $0 == "-" }) {
            s = String(s[..<i])
        }
        let parts = s.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.components = parts
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxLen = max(lhs.components.count, rhs.components.count)
        for i in 0..<maxLen {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }
}

/// UpdateService 的状态机，用于 UI 展示 / 按钮可用性。
enum UpdateCheckState: Equatable {
    case idle                       // 未检查过
    case checking                   // 正在拉 GitHub API
    case upToDate(Date)             // 已是最新（带上次检查时间）
    case available(ReleaseInfo)     // 有新版可用
    case error(String, Date)        // 检查失败（消息 + 时间）
}

extension UpdateCheckState {
    /// 上一次成功 / 失败检查的时间戳，用于 Settings 里展示"上次检查 xx 分钟前"。
    var lastCheckedAt: Date? {
        switch self {
        case .upToDate(let d), .error(_, let d): return d
        case .available, .idle, .checking: return nil
        }
    }
}
