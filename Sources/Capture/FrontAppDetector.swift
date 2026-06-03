import Foundation
import AppKit

/// 抓取当前前台 app 名 + 该 app 当前窗口标题（用作 AI 的辅助 context）。
@MainActor
enum FrontAppDetector {
    struct Result {
        let appName: String
        let windowTitles: String  // 用逗号拼接
    }

    static func detect() -> Result {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return Result(appName: "Unknown", windowTitles: "")
        }
        let name = app.localizedName ?? "Unknown"
        let pid = app.processIdentifier

        // CGWindowList 取该 app 的所有可见窗口标题
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return Result(appName: name, windowTitles: "")
        }
        let titles = infos.compactMap { info -> String? in
            guard let winPid = info[kCGWindowOwnerPID as String] as? Int32, winPid == pid else { return nil }
            guard let title = info[kCGWindowName as String] as? String, !title.isEmpty else { return nil }
            return title
        }
        return Result(appName: name, windowTitles: titles.joined(separator: ", "))
    }
}
