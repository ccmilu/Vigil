import Foundation
import AppKit

/// 在 Dock 图标右上角显示剩余分钟数（如 "24"）。
/// MVP 用 badgeLabel；环形进度图标留到 v0.2。
@MainActor
enum DockBadge {
    static func setRemaining(seconds: Int?) {
        let tile = NSApp.dockTile
        guard let s = seconds else {
            tile.badgeLabel = nil
            tile.display()
            return
        }
        if s <= 0 {
            tile.badgeLabel = "✓"
        } else if s >= 60 {
            tile.badgeLabel = "\(s / 60)"
        } else {
            tile.badgeLabel = "<1"
        }
        // macOS 26 上 badgeLabel 赋值偶尔不立刻刷新，强制 redraw 一次
        tile.display()
    }
}
