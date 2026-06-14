import Foundation

/// GitHub Releases API 客户端：拉最新 release + 解析。
///
/// 无状态，节流由 UpdateService 控制；这里只负责 "发请求 -> 拿 JSON -> 解析"。
struct UpdateChecker {
    /// 仓库 owner/name，公开仓库无需 token。
    static let repository = "ccmilu/Vigil"

    /// UpdateService 用来限制最小请求间隔（防误操作）。
    static let minRequestInterval: TimeInterval = 60

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private static var endpoint: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    enum CheckError: LocalizedError {
        case http(Int)
        case decode(String)

        // 走 L() 而非 LocalizedStringKey：errorDescription 是 Foundation 接口，
        // 下游可能被 AppKit / 错误日志消费，必须返回当前语言的 String
        var errorDescription: String? {
            switch self {
            case .http(let code): return L("GitHub 返回 HTTP %lld", args: code as CVarArg)
            case .decode(let msg): return L("响应解析失败：%@", args: msg as CVarArg)
            }
        }
    }

    func fetchLatestRelease() async throws -> ReleaseInfo {
        var req = URLRequest(url: Self.endpoint)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Vigil-Updater/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CheckError.http(http.statusCode)
        }
        return try Self.decode(data)
    }

    /// 静态、纯函数，便于测试。
    static func decode(_ data: Data) throws -> ReleaseInfo {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CheckError.decode(L("根对象不是 JSON 字典"))
        }
        guard let tagName = root["tag_name"] as? String,
              let version = SemanticVersion(tagName) else {
            throw CheckError.decode(L("缺失 tag_name 或解析失败"))
        }
        let name = (root["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tagName
        let body = (root["body"] as? String) ?? ""
        let htmlURL: URL = {
            if let s = root["html_url"] as? String, let u = URL(string: s) { return u }
            return URL(string: "https://github.com/\(repository)/releases")!
        }()
        let publishedAt: Date? = {
            guard let s = root["published_at"] as? String else { return nil }
            return ISO8601DateFormatter().date(from: s)
        }()

        // 在 assets 里找第一个 .dmg
        var dmgURL: URL?
        if let assets = root["assets"] as? [[String: Any]] {
            for asset in assets {
                if let assetName = asset["name"] as? String,
                   assetName.lowercased().hasSuffix(".dmg"),
                   let urlString = asset["browser_download_url"] as? String,
                   let url = URL(string: urlString) {
                    dmgURL = url
                    break
                }
            }
        }

        return ReleaseInfo(
            tagName: tagName,
            name: name,
            version: version,
            body: body,
            htmlURL: htmlURL,
            dmgURL: dmgURL,
            publishedAt: publishedAt
        )
    }
}
